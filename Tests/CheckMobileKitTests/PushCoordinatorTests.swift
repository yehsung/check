import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

/// 푸시 코디네이터 시나리오(스텁 서버 · 가짜 시스템 · 주입 시계). 모든 시나리오 끝에 **폰 금지 호출 0건**을 단언한다.
@MainActor
@Suite(.serialized) struct PushCoordinatorTests {
    // MARK: - 권한 · 등록

    @Test("로그인 뒤 앞에 있고 권한 미결정 → 설명 시트 → 알림 켜기 → 허락 → 원격 등록 1회 → 토큰 hex · sandbox 로 register_device")
    func primerAllowRegistersToken() async throws {
        let h = PushHarness()
        defer { h.tearDown() }
        await h.launchSignedIn()

        #expect(h.push.isPrimerPresented)
        #expect(h.system.primerPresentations == 1)
        #expect(h.system.authorizationRequests == 0, "설명 시트보다 시스템 창이 먼저 뜨면 안 된다")
        #expect(h.system.remoteRegistrations == 0)
        #expect(h.push.authorization == .notDetermined)

        await h.push.primerAllow()
        await h.settle()
        #expect(!h.push.isPrimerPresented)
        #expect(h.system.primerDismissals == 1)
        #expect(h.system.authorizationRequests == 1)
        #expect(h.push.authorization == .authorized)
        #expect(h.system.remoteRegistrations == 1)

        h.clearRequests()
        h.model.didRegisterForRemoteNotifications(deviceToken: PushHarness.deviceToken)
        await h.settle()
        let register = try #require(h.calls("register_device").last)
        #expect(pushBodyValue(register, "p_apns_token") as? String == PushTokenFormatter.hex(PushHarness.deviceToken))
        #expect(pushBodyValue(register, "p_apns_env") as? String == "sandbox")
        #expect(pushBodyValue(register, "p_platform") as? String == "ios")

        // 같은 토큰이 다시 와도 다시 등록하지 않는다 · 다시 active 가 돼도 원격 등록은 실행마다 한 번.
        h.clearRequests()
        h.model.didRegisterForRemoteNotifications(deviceToken: PushHarness.deviceToken)
        h.model.sceneDidEnterBackground()
        h.model.sceneDidBecomeActive()
        await h.settle()
        #expect(h.calls("register_device").isEmpty)
        #expect(h.system.remoteRegistrations == 1)
        #expect(h.forbiddenViolations.isEmpty)
    }

    @Test("나중에 → 7일 동안 다시 묻지 않고 7일 뒤 다시 · 이미 허락이면 시트 없이 등록 · 거절이면 시트도 등록도 없음")
    func primerCooldownAndStatuses() async {
        let h = PushHarness()
        defer { h.tearDown() }
        await h.launchSignedIn()
        #expect(h.push.isPrimerPresented)
        h.push.primerLater()
        #expect(!h.push.isPrimerPresented)
        #expect(h.system.authorizationRequests == 0)

        h.clock.advance(6 * 24 * 3600)
        h.model.sceneDidEnterBackground()
        h.model.sceneDidBecomeActive()
        await h.settle()
        #expect(!h.push.isPrimerPresented, "쉬는 기간 안에 다시 물었다")

        h.clock.advance(24 * 3600 + 1)
        h.model.sceneDidEnterBackground()
        h.model.sceneDidBecomeActive()
        await h.settle()
        #expect(h.push.isPrimerPresented, "7일이 지나면 다시 묻는다")
        // 끌어내려 닫기 = 나중에
        h.push.primerDidDisappear()
        #expect(!h.push.isPrimerPresented)

        // 설정 앱에서 켰다 → active 에서 시트 없이 등록
        h.system.status = .authorized
        h.model.sceneDidEnterBackground()
        h.model.sceneDidBecomeActive()
        await h.settle()
        #expect(h.system.remoteRegistrations == 1)
        #expect(h.system.primerPresentations == 2)

        let denied = PushHarness(label: "push-denied")
        defer { denied.tearDown() }
        denied.system.status = .denied
        await denied.launchSignedIn()
        #expect(!denied.push.isPrimerPresented)
        #expect(denied.system.remoteRegistrations == 0)
        #expect(denied.push.authorizationText == PushText.settingsDenied)
        // 설정 화면의 "알림 켜기" — 거절 상태면 설정 앱으로
        await denied.push.enableNotifications()
        #expect(denied.system.settingsOpened == 1)
        #expect(denied.system.authorizationRequests == 0)

        #expect(h.forbiddenViolations.isEmpty)
        #expect(denied.forbiddenViolations.isEmpty)
    }

    @Test("로그아웃 뒤 다시 로그인: 끊었던 원격 등록을 권한이 있으면 다시 한다 · 치명 만료도 같은 정리")
    func reRegistersAfterSignOut() async {
        let h = PushHarness()
        h.system.status = .authorized
        defer { h.tearDown() }
        await h.launchSignedIn()
        #expect(h.system.remoteRegistrations == 1)
        await h.model.session.signOut()
        #expect(h.system.remoteUnregistrations == 1)
        await h.model.session.signIn(email: "push@aing-check.invalid", password: "pw")
        await h.settle()
        #expect(h.system.remoteRegistrations == 2)

        h.model.session.expireSession()
        #expect(h.system.remoteUnregistrations == 2)
        #expect(h.system.deliveredRemovals == 2)
        #expect(h.forbiddenViolations.isEmpty)
    }

    @Test("앱이 뒤에 있을 때 로그인(알림 액션으로 깨어남)이면 시트를 띄우지 않는다 · 데모 조립은 명시하지 않으면 시트 없음")
    func noPrimerInBackgroundOrDemo() async {
        let h = PushHarness()
        defer { h.tearDown() }
        await h.launchSignedIn(active: false)
        #expect(h.system.statusReads >= 1)
        #expect(!h.push.isPrimerPresented)

        MobileStubURLProtocol.clearRequests(host: MobileDemo.host)
        let environment = MobileDemo.environment(arguments: ["app", "-AingCheckDemo", "YES", "-AingCheckDemoRoute", "now"])!
        let demo = MobileAppModel(environment: environment)
        let system = PushFakeSystem()
        demo.push.attach(system: system)
        demo.start()
        #expect(await baseWaitUntil { demo.session.isSignedIn })
        demo.sceneDidBecomeActive()
        await demo.push.pendingStatusCheck?.value
        #expect(!demo.push.isPrimerPresented, "데모 스크린샷(다른 탭)이 시트에 가린다")

        let forced = MobileAppModel(environment: MobileDemo.environment(arguments: ["app", "-AingCheckDemo", "YES", "-AingCheckDemoRoute", "now"])!)
        let forcedSystem = PushFakeSystem()
        forced.push.attach(system: forcedSystem)
        forced.applyPushDemoArguments(["app", "-AingCheckDemo", "YES", "-AingCheckDemoPushPrimer", "YES"])
        forced.start()
        #expect(await baseWaitUntil { forced.session.isSignedIn })
        forced.sceneDidBecomeActive()
        #expect(await baseWaitUntil { forced.push.isPrimerPresented })
        #expect(forcedSystem.primerPresentations == 1)
        await forced.push.pendingStatusCheck?.value
        await forced.session.pendingDeviceRegistration?.value
        await baseBarrier(forced.context.service)
        #expect(MobileForbiddenCalls.violations(in: MobileStubURLProtocol.requests(host: MobileDemo.host)).isEmpty)
        #expect(h.forbiddenViolations.isEmpty)
    }

    @Test("로그아웃(reset): 시트를 내리고 배지를 0 으로, 늦게 끝난 권한 확인은 새 세대에 시트·등록을 만들지 않는다")
    func resetDropsLateStatus() async {
        let h = PushHarness()
        defer { h.tearDown() }
        await h.launchSignedIn()
        #expect(h.push.isPrimerPresented)
        h.model.didRegisterForRemoteNotifications(deviceToken: PushHarness.deviceToken)
        #expect(h.model.session.apnsToken == PushTokenFormatter.hex(PushHarness.deviceToken))
        #expect(h.system.deliveredRemovals == 0 && h.system.remoteUnregistrations == 0)
        await h.model.session.signOut()
        #expect(!h.push.isPrimerPresented)
        #expect(h.system.primerDismissals == 1)
        #expect(h.system.badgeCounts.last == 0)
        #expect(h.system.deliveredRemovals == 1, "앞 계정 알림이 알림 센터에 남았다")
        #expect(h.system.remoteUnregistrations == 1, "원격 등록을 끊지 않았다")
        #expect(h.model.session.apnsToken == nil, "끊은 토큰을 다음 계정 등록에 실었다")

        // 느린 권한 확인(시스템 콜백은 취소를 모른다)이 떠 있는 동안 로그아웃 → 곧바로 다시 로그인.
        // 앞 세대에서 시작한 확인은 "허락"을 읽었고, 지금 기기는 "거절"이다 — 늦게 온 앞 결과가 새 세대에 등록·표시를 만들면 안 된다.
        h.system.status = .authorized
        let slowStatus = BaseGate()
        h.system.statusGate = slowStatus
        let reads = h.system.statusReads
        await h.model.session.signIn(email: "push@aing-check.invalid", password: "pw")
        #expect(await baseWaitUntil { h.system.statusReads > reads && slowStatus.arrivals == 1 }, "권한 확인이 시작되지 않았다")
        let lateCheck = h.push.pendingStatusCheck
        h.system.status = .denied
        await h.model.session.signOut()
        h.system.statusGate = nil
        await h.model.session.signIn(email: "push@aing-check.invalid", password: "pw")
        // 새 세대의 로그인이 끝난 **뒤에** 앞 세대 확인("허락")이 돌아온다.
        slowStatus.open()
        await lateCheck?.value
        await h.settle()
        #expect(h.system.remoteRegistrations == 0, "로그아웃 전에 시작한 권한 확인이 새 세대에서 원격 등록을 했다")
        #expect(h.push.authorization == .denied, "늦게 온 앞 세대 권한 값이 화면 값을 덮었다")
        #expect(h.forbiddenViolations.isEmpty)
    }

    // MARK: - 포그라운드 표시

    @Test("포그라운드: 지금 보고 있는 대화의 메시지만 숨긴다 — 다른 대화 · 뒤에 있음 · 오목 · 제보는 배너, 오목 신청은 받은함 재조회")
    func foregroundPresentation() async {
        let h = PushHarness()
        h.system.status = .authorized
        defer { h.tearDown() }
        await h.launchSignedIn()
        h.setRPC("gomoku_inbox", .json(#"{"status":"ok","incoming":[],"outgoing":null,"active_match_id":null}"#))

        let message = PushPayload(userInfo: PushHarness.messageUserInfo())
        #expect(h.push.presentation(for: message) == .banner, "대화를 안 보고 있다")
        h.model.router.visibleConversationPeerID = PushHarness.peerID.uppercased()
        #expect(h.push.presentation(for: message) == .hidden)
        #expect(h.push.presentation(for: PushPayload(userInfo: PushHarness.messageUserInfo(peer: "other-peer"))) == .banner)
        h.model.sceneDidEnterBackground()
        #expect(h.push.presentation(for: message) == .banner, "뒤에 있으면 대화가 보이는 것이 아니다")
        h.model.sceneDidBecomeActive()
        await h.settle()

        h.clearRequests()
        #expect(h.push.presentation(for: PushPayload(userInfo: PushHarness.gomokuUserInfo())) == .banner)
        #expect(await baseWaitUntil { !h.calls("gomoku_inbox").isEmpty }, "오목 신청 알림이 받은함을 다시 읽지 않았다")
        #expect(h.push.presentation(for: PushPayload(userInfo: PushHarness.feedbackUserInfo())) == .banner)
        #expect(h.push.presentation(for: nil) == .banner, "모르는 알림(앱이 띄운 안내 등)은 그대로 보인다")
        #expect(h.model.router.lastOpenedRoute == nil, "표시만으로 화면을 바꾸면 안 된다")
        #expect(h.forbiddenViolations.isEmpty)
    }

    // MARK: - 탭 → 라우트

    @Test("탭 → 라우트: 메시지 → 대화 · 오목 신청 → 신청 · 제보 답장 → 그 제보(id 없으면 목록)")
    func tapRoutes() async {
        let h = PushHarness()
        h.system.status = .authorized
        defer { h.tearDown() }
        await h.launchSignedIn()

        await h.push.handleResponse(PushPayload(userInfo: PushHarness.messageUserInfo()), action: .open)
        #expect(h.model.router.selectedTab == .messages)
        #expect(h.model.router.consumePendingRoute(for: .messages) == .message(peerID: PushHarness.peerID))

        await h.push.handleResponse(PushPayload(userInfo: PushHarness.gomokuUserInfo()), action: .open)
        #expect(h.model.router.selectedTab == .games)
        #expect(h.model.router.consumePendingRoute(for: .games) == .gomokuInvite(matchID: PushHarness.matchID))

        await h.push.handleResponse(PushPayload(userInfo: PushHarness.feedbackUserInfo()), action: .open)
        #expect(h.model.router.consumePendingRoute(for: .me) == .feedback(reportID: PushHarness.reportID))
        await h.push.handleResponse(PushPayload(userInfo: PushHarness.feedbackUserInfo(report: nil)), action: .open)
        #expect(h.model.router.consumePendingRoute(for: .me) == .feedback(reportID: nil))

        // 모르는 알림 · 지우기 액션은 아무것도 열지 않는다
        h.model.router.reset()
        await h.push.handleResponse(nil, action: .open)
        await h.push.handleResponse(PushPayload(userInfo: PushHarness.messageUserInfo()), action: .ignore)
        #expect(h.model.router.lastOpenedRoute == .feedback(reportID: nil))
        #expect(h.model.router.selectedTab == .now)
        #expect(h.forbiddenViolations.isEmpty)
    }

    @Test("알림을 눌러 앱이 켜짐: 실행 복원(.launching) 중에 온 탭은 복원 뒤 열린다 — 복원이 로그아웃으로 끝나면 열지 않는다")
    func tapDuringLaunch() async {
        let h = PushHarness()
        h.system.status = .authorized
        defer { h.tearDown() }
        // 키체인에 세션이 있고 client_release 가 느리다
        let vaultEnvironment = MobileEnvironment(
            service: BaseStub.makeService(host: h.host),
            vault: {
                let vault = InMemoryTokenVault()
                vault.write(h.access, key: AingKeychain.accessTokenKey)
                vault.write("r1", key: AingKeychain.refreshTokenKey)
                return vault
            }(),
            storage: h.storage,
            appInfo: BaseStub.appInfo,
            clock: h.clock.clock,
            installationID: "11111111-2222-4333-8444-555555555555",
            realtimeTransport: nil,
            runsTimers: false,
            reloadWidgetTimelines: {}
        )
        h.storage.defaults.set(PushHarness.userID, forKey: AingSharedKeys.userID)
        h.setRPC("client_release", .json(#"{"status":"ok","platform":"ios","min_build":1,"latest_build":1}"#))
        let slowRelease = BaseHold.rpc("client_release", host: h.host)
        let model = MobileAppModel(environment: vaultEnvironment)
        model.push.attach(system: h.system)
        model.push.sessionSettleTimeoutSeconds = BaseStub.patientSeconds
        model.session.clientReleaseTimeoutSeconds = 0
        #expect(model.session.phase == .launching)
        model.start()
        let tap = Task { await model.push.handleResponse(PushPayload(userInfo: PushHarness.messageUserInfo()), action: .open) }
        #expect(await slowRelease.waitHeld())
        #expect(model.session.phase == .launching, "전제: 복원이 아직 떠 있다")
        #expect(await slowRelease.releaseAndWaitDelivered())
        await tap.value
        #expect(model.session.isSignedIn)
        #expect(model.router.consumePendingRoute(for: .messages) == .message(peerID: PushHarness.peerID))

        // 대조: 키체인이 비어 로그아웃으로 끝나면 열지 않는다
        let empty = PushHarness(label: "push-empty")
        defer { empty.tearDown() }
        empty.push.attach(system: empty.system)
        empty.model.start()
        await empty.push.handleResponse(PushPayload(userInfo: PushHarness.gomokuUserInfo()), action: .open)
        #expect(empty.model.session.phase == .signedOut)
        #expect(empty.model.router.lastOpenedRoute == nil)
        // 답장이었다면 로그인 안내를 알림으로 남긴다(적은 글이 말없이 사라지지 않게)
        await empty.push.handleResponse(PushPayload(userInfo: PushHarness.messageUserInfo()), action: .reply("곧 가요"))
        #expect(empty.system.notices.last?.body == PushText.replyNeedsSignIn)
        #expect(empty.calls("send_message").isEmpty)
        #expect(MobileForbiddenCalls.violations(in: MobileStubURLProtocol.requests(host: h.host)).isEmpty)
        #expect(empty.forbiddenViolations.isEmpty)
    }

    // MARK: - 답장 · 읽음

    @Test("답장: 이 계정의 받은 메시지인지 확인 → send_message(p_to, p_body) → mark_messages_read(p_peer, p_through=그 메시지) 순서")
    func replySendsThenMarks() async throws {
        let h = PushHarness()
        h.system.status = .authorized
        defer { h.tearDown() }
        await h.launchSignedIn(active: false)
        h.setRPC("message_history_with_reads", PushHarness.historyWithReceived())
        h.setRPC("send_message", .json(#"{"status":"ok"}"#))
        h.setRPC("mark_messages_read", .json(#"{"status":"ok","advanced":true,"unread":0}"#))
        h.clearRequests()

        await h.push.handleResponse(PushPayload(userInfo: PushHarness.messageUserInfo()), action: .reply("  곧 가요  "))
        let names = h.requests().compactMap(\.rpcName)
        // 뒤따르는 요약 읽기는 앱 배지 확인(뒤에서 켜진 실행 — PushBadgeTests)이다.
        #expect(names == ["message_history_with_reads", "send_message", "mark_messages_read", "message_unread_summary"], "\(names)")
        let send = try #require(h.calls("send_message").first)
        #expect(pushBodyValue(send, "p_to") as? String == PushHarness.peerID)
        #expect((pushBodyValue(send, "p_body") as? String)?.contains("곧 가요") == true)
        let mark = try #require(h.calls("mark_messages_read").first)
        #expect(pushBodyValue(mark, "p_peer") as? String == PushHarness.peerID)
        #expect(pushBodyValue(mark, "p_through") as? String == PushHarness.messageID)
        #expect(h.system.notices.isEmpty)
        #expect(h.model.router.lastOpenedRoute == nil, "백그라운드 답장이 화면을 바꾸면 안 된다")
        #expect(h.forbiddenViolations.isEmpty)
    }

    @Test("답장 대조: 지금 계정 이력에 없는 메시지(앞 계정 알림)면 보내지 않고 안내 알림 · 읽음 칸 함수가 없는 서버는 옛 이력으로 확인")
    func replyRefusesForeignMessage() async {
        let h = PushHarness()
        h.system.status = .authorized
        defer { h.tearDown() }
        await h.launchSignedIn(active: false)
        h.setRPC("message_history_with_reads", PushHarness.historyWithReceived(id: "99999999-0000-4000-8000-000000000000"))
        h.setRPC("send_message", .json(#"{"status":"ok"}"#))
        h.setRPC("mark_messages_read", .json(#"{"status":"ok","advanced":true,"unread":0}"#))
        h.clearRequests()

        await h.push.handleResponse(PushPayload(userInfo: PushHarness.messageUserInfo()), action: .reply("곧 가요"))
        #expect(h.calls("send_message").isEmpty, "다른 계정 이름으로 보냈다")
        #expect(h.calls("mark_messages_read").isEmpty)
        #expect(h.system.notices.count == 1)
        #expect(h.system.notices.first?.title == PushText.replyFailedTitle)
        #expect(h.system.notices.first?.body == PushText.replyMessageGone)
        #expect(h.system.notices.first?.threadID == "message-\(PushHarness.peerID)")

        // 옛 서버: with_reads 없음(404 PGRST202) → message_history 로 확인해 보낸다
        h.setRPC("message_history_with_reads", .missingFunction("message_history_with_reads"))
        h.setRPC("message_history", PushHarness.historyWithReceived())
        h.clearRequests()
        await h.push.handleResponse(PushPayload(userInfo: PushHarness.messageUserInfo()), action: .reply("곧 가요"))
        #expect(h.requests().compactMap(\.rpcName) == ["message_history_with_reads", "message_history", "send_message", "mark_messages_read", "message_unread_summary"])

        // message_id 가 없는 알림: 확인할 수 없으니 보내지 않는다
        h.clearRequests()
        await h.push.handleResponse(PushPayload(userInfo: PushHarness.messageUserInfo(message: nil)), action: .reply("곧 가요"))
        #expect(h.requests().compactMap(\.rpcName).isEmpty)
        #expect(h.forbiddenViolations.isEmpty)
    }

    @Test("답장 실패: 서버 거절은 맥과 같은 문장으로 안내하고 읽음은 올린다 · 네트워크 실패는 연결 안내 · 빈 답장은 보내지 않고 읽음만")
    func replyFailures() async {
        let h = PushHarness()
        h.system.status = .authorized
        defer { h.tearDown() }
        await h.launchSignedIn(active: false)
        h.setRPC("message_history_with_reads", PushHarness.historyWithReceived())
        h.setRPC("mark_messages_read", .json(#"{"status":"ok","advanced":true,"unread":0}"#))

        h.setRPC("send_message", .json(#"{"status":"target_focused"}"#))
        await h.push.handleResponse(PushPayload(userInfo: PushHarness.messageUserInfo()), action: .reply("곧 가요"))
        #expect(h.system.notices.last?.body == MessageNoticeText.targetFocused)
        #expect(h.calls("mark_messages_read").count == 1)

        h.setRPC("send_message", .networkFailure())
        await h.push.handleResponse(PushPayload(userInfo: PushHarness.messageUserInfo()), action: .reply("곧 가요"))
        #expect(h.system.notices.last?.body == PushText.connectionUnstable)

        h.clearRequests()
        let before = h.system.notices.count
        await h.push.handleResponse(PushPayload(userInfo: PushHarness.messageUserInfo()), action: .reply("   \n "))
        #expect(h.calls("send_message").isEmpty)
        #expect(h.calls("mark_messages_read").count == 1)
        #expect(h.system.notices.count == before)
        #expect(h.forbiddenViolations.isEmpty)
    }

    @Test("백그라운드 답장 안의 401: 세션 조정자 경유로 한 번 갱신하고 새 토큰으로 다시 보낸다(로그아웃하지 않는다)")
    func replyRefreshesSessionOn401() async throws {
        let h = PushHarness()
        h.system.status = .authorized
        defer { h.tearDown() }
        await h.launchSignedIn(active: false)
        h.setRPC("message_history_with_reads", PushHarness.historyWithReceived())
        h.setRPC("send_message", .json(#"{"status":"ok"}"#))
        h.setRPC("mark_messages_read", .json(#"{"status":"ok","advanced":true,"unread":0}"#))
        h.clearRequests()
        h.firstCallOverride.mutate { $0["message_history_with_reads"] = BaseStub.jwtExpired }

        await h.push.handleResponse(PushPayload(userInfo: PushHarness.messageUserInfo()), action: .reply("곧 가요"))
        let refreshes = h.requests().filter { $0.path == "/auth/v1/token" && $0.queryValue("grant_type") == "refresh_token" }
        #expect(refreshes.count == 1)
        #expect(h.model.session.isSignedIn)
        #expect(h.model.session.session?.accessToken == h.refreshed)
        let send = try #require(h.calls("send_message").first)
        #expect(BaseStub.bearer(send) == "Bearer \(h.refreshed)")
        #expect(h.calls("mark_messages_read").count == 1)
        #expect(h.system.notices.isEmpty)
        #expect(h.forbiddenViolations.isEmpty)
    }

    @Test("읽음 액션: 그 메시지까지만 mark · message_id 없으면 서버 왕복 0")
    func markReadAction() async throws {
        let h = PushHarness()
        h.system.status = .authorized
        defer { h.tearDown() }
        await h.launchSignedIn(active: false)
        h.setRPC("mark_messages_read", .json(#"{"status":"ok","advanced":true,"unread":2}"#))
        h.clearRequests()

        await h.push.handleResponse(PushPayload(userInfo: PushHarness.messageUserInfo()), action: .markRead)
        #expect(h.requests().compactMap(\.rpcName) == ["mark_messages_read", "message_unread_summary"], "읽음 뒤 배지 확인만 따른다")
        let mark = try #require(h.calls("mark_messages_read").first)
        #expect(pushBodyValue(mark, "p_through") as? String == PushHarness.messageID)

        h.clearRequests()
        await h.push.handleResponse(PushPayload(userInfo: PushHarness.messageUserInfo(message: nil)), action: .markRead)
        #expect(h.requests().isEmpty, "경계 없이 최신까지 읽음을 올렸다")
        // 카테고리와 맞지 않는 액션(오목 알림에 읽음)은 아무것도 하지 않는다
        await h.push.handleResponse(PushPayload(userInfo: PushHarness.gomokuUserInfo()), action: .markRead)
        #expect(h.requests().isEmpty)
        #expect(h.forbiddenViolations.isEmpty)
    }

    // MARK: - 오목 수락 · 거절

    @Test("수락: gomoku_respond(accept) → 판이 열리면 대국으로 · 만료면 신청 화면으로 · 거절: respond(false) 만, 화면 안 바뀜")
    func gomokuAcceptDecline() async throws {
        let h = PushHarness()
        h.system.status = .authorized
        defer { h.tearDown() }
        await h.launchSignedIn()
        h.setRPC("gomoku_respond", PushHarness.respondAcceptOK())
        h.setRPC("gomoku_state", .json(#"{"status":"not_found"}"#))
        h.clearRequests()

        await h.push.handleResponse(PushPayload(userInfo: PushHarness.gomokuUserInfo()), action: .acceptInvite)
        let respond = try #require(h.calls("gomoku_respond").first)
        #expect(pushBodyValue(respond, "p_match_id") as? String == PushHarness.matchID)
        #expect(pushBodyValue(respond, "p_accept") as? Bool == true)
        #expect(h.model.gomoku.match?.id == PushHarness.matchID)
        #expect(h.model.router.lastOpenedRoute == .gomokuMatch(matchID: PushHarness.matchID))
        #expect(h.model.gomokuHost.rubyBalance == 95 || h.model.gomoku.rubyBalance == 95)

        let expired = PushHarness(label: "push-expired")
        expired.system.status = .authorized
        defer { expired.tearDown() }
        await expired.launchSignedIn()
        expired.setRPC("gomoku_respond", .json(#"{"status":"expired","ruby_balance":100}"#))
        await expired.push.handleResponse(PushPayload(userInfo: PushHarness.gomokuUserInfo()), action: .acceptInvite)
        #expect(expired.model.router.lastOpenedRoute == .gomokuInvite(matchID: PushHarness.matchID))
        #expect(expired.model.gomoku.notice == GomokuNoticeText.respond(accept: true, .expired))

        expired.clearRequests()
        expired.model.router.reset()
        expired.setRPC("gomoku_respond", .json(#"{"status":"ok","accepted":false,"ruby_balance":100}"#))
        await expired.push.handleResponse(PushPayload(userInfo: PushHarness.gomokuUserInfo()), action: .declineInvite)
        let decline = try #require(expired.calls("gomoku_respond").first)
        #expect(pushBodyValue(decline, "p_accept") as? Bool == false)
        #expect(expired.model.router.lastOpenedRoute == .gomokuInvite(matchID: PushHarness.matchID), "거절은 새 화면을 열지 않는다(앞의 기록 그대로)")
        #expect(expired.model.router.selectedTab == .now)
        #expect(h.forbiddenViolations.isEmpty)
        #expect(expired.forbiddenViolations.isEmpty)
    }

    // MARK: - 앱 배지

    @Test("앱 배지 = 메시지 + 게임 배지 합을 관찰해 바뀔 때마다 적고(서버 확인 뒤), 로그아웃이면 0")
    func appBadgeFollowsTabBadges() async {
        let h = PushHarness()
        h.system.status = .authorized
        defer { h.tearDown() }
        let badges = PushFakeBadges()
        h.push.badgeTotalSource = { badges.messages + badges.games }
        h.setRPC("message_unread_summary", PushHarness.unreadSummary(total: 0))
        await h.launchSignedIn()
        #expect(h.push.badgeState == .stores)
        #expect(h.system.badgeCounts.last == 0)

        badges.messages = 3
        #expect(await baseWaitUntil { h.system.badgeCounts.last == 3 })
        badges.games = 2
        #expect(await baseWaitUntil { h.system.badgeCounts.last == 5 })
        let writes = h.system.badgeCounts.count
        // 같은 합: 재료는 바뀌었는데(관찰이 깨어난다) 합은 5 그대로 — 다시 적지 않는다. (같은 값 대입은 Observation 이 알리지 않아 재지 못한다.)
        badges.messages = 4
        badges.games = 1
        await baseYield()
        #expect(h.system.badgeCounts.count == writes, "같은 값을 다시 적었다")
        // 사건 순서 대조: 뒤에 바꾼 다른 값은 한 번만 적힌다(같은 값이 적혔다면 그보다 앞에 끼었다).
        badges.messages = 5
        #expect(await baseWaitUntil { h.system.badgeCounts.last == 6 })
        #expect(h.system.badgeCounts.count == writes + 1, "같은 값을 다시 적었다: \(h.system.badgeCounts)")

        await h.model.session.signOut()
        #expect(await baseWaitUntil { h.system.badgeCounts.last == 0 })
        #expect(h.push.badgeState == .unknown)
        let signedOutWrites = h.system.badgeCounts.count
        badges.messages = 9
        await baseYield()
        await h.barrier()
        #expect(h.system.badgeCounts.last == 0, "로그아웃 상태에서 배지를 올렸다")
        #expect(h.system.badgeCounts.count == signedOutWrites)

        // 기본 출처는 탭 배지 합(자리 스토어는 0) — 링크가 채워진 모델에서 0 을 읽는다
        #expect(h.model.links.badges.appBadgeTotal == 0)
        #expect(h.forbiddenViolations.isEmpty)
    }

    // MARK: - 알림 설정(나 탭 공개 API)

    @Test("알림 설정: 저장 중엔 누른 값 · set_push_prefs 본문 3키 · not_found 면 등록을 기다려 한 번 더 · 네트워크 실패는 안내 한 줄")
    func preferences() async throws {
        let h = PushHarness()
        h.system.status = .authorized
        defer { h.tearDown() }
        await h.launchSignedIn()
        #expect(h.push.prefs == PushPrefs(message: true, gomokuInvite: false, feedbackReply: true), "register_device 응답의 설정")

        h.setRPC("set_push_prefs", .json(#"{"status":"ok","push_prefs":{"message":false,"gomoku_invite":false,"feedback_reply":true}}"#))
        h.clearRequests()
        let saveHold = BaseHold.rpc("set_push_prefs", host: h.host)
        let saving = Task { await h.push.setPreference(.message, enabled: false) }
        #expect(await baseWaitUntil { h.push.isSavingPrefs })
        #expect(await saveHold.waitHeld())
        #expect(!h.push.isEnabled(.message), "저장 중에 누른 값이 보이지 않는다")
        #expect(await saveHold.releaseAndWaitDelivered())
        #expect(await saving.value)
        #expect(!h.push.isSavingPrefs)
        #expect(h.push.prefs == PushPrefs(message: false, gomokuInvite: false, feedbackReply: true))
        let save = try #require(h.calls("set_push_prefs").first)
        let sent = try #require(pushBodyValue(save, "p_prefs") as? [String: Any])
        #expect(sent["message"] as? Bool == false && sent["gomoku_invite"] as? Bool == false && sent["feedback_reply"] as? Bool == true)
        #expect(pushBodyValue(save, "p_installation_id") as? String == "11111111-2222-4333-8444-555555555555")

        // not_found → register_device → 다시 저장
        h.clearRequests()
        h.firstCallOverride.mutate { $0["set_push_prefs"] = .json(#"{"status":"not_found"}"#) }
        h.setRPC("set_push_prefs", .json(#"{"status":"ok","push_prefs":{"message":false,"gomoku_invite":true,"feedback_reply":true}}"#))
        #expect(await h.push.setPreference(.gomokuInvite, enabled: true))
        #expect(h.requests().compactMap(\.rpcName) == ["set_push_prefs", "register_device", "set_push_prefs"])

        // 네트워크 실패 → 안내, 값은 서버가 마지막으로 준 것으로 돌아간다
        h.setRPC("set_push_prefs", .networkFailure())
        #expect(await h.push.setPreference(.feedbackReply, enabled: false) == false)
        #expect(h.push.prefsNotice == PushText.settingsSaveFailed)
        #expect(h.push.isEnabled(.feedbackReply))
        #expect(h.model.session.isSignedIn, "일시 실패로 로그아웃했다")
        #expect(h.forbiddenViolations.isEmpty)
    }

    @Test("알림 켜기 버튼: 미결정이면 시스템 창 → 허락 → 등록 · 등록 실패 콜백 뒤 다음 active 에 다시 등록")
    func enableFromSettingsAndRetryAfterFailure() async {
        let h = PushHarness()
        defer { h.tearDown() }
        await h.launchSignedIn()
        h.push.primerLater()
        #expect(h.push.authorizationText == PushText.settingsNotDetermined)
        await h.push.enableNotifications()
        #expect(h.system.authorizationRequests == 1)
        #expect(h.push.authorization == .authorized)
        #expect(h.system.remoteRegistrations == 1)

        h.model.didFailToRegisterForRemoteNotifications(error: URLError(.notConnectedToInternet))
        #expect(h.push.lastRegistrationError != nil)
        h.model.sceneDidEnterBackground()
        h.model.sceneDidBecomeActive()
        await h.settle()
        #expect(h.system.remoteRegistrations == 2)
        #expect(h.forbiddenViolations.isEmpty)
    }

    // MARK: - push-verify 수리 회귀

    @Test("답장 중 치명 만료(이력 401 → 갱신 invalid_grant): 보내지 않고, 알림 센터를 비운 **뒤에** 로그인 안내를 남긴다 · 보내기 단계의 만료도 같다")
    func replyDuringFatalExpiryLeavesNotice() async throws {
        for stage in ["history", "send"] {
            let h = PushHarness(label: "push-fatal-\(stage)")
            h.system.status = .authorized
            defer { h.tearDown() }
            await h.launchSignedIn(active: false)
            h.setRPC("message_history_with_reads", PushHarness.historyWithReceived())
            h.setRPC("send_message", .json(#"{"status":"ok"}"#))
            h.setRPC("mark_messages_read", .json(#"{"status":"ok","advanced":true,"unread":0}"#))
            // 응답기 교체: 그 단계의 RPC 는 언제나 401, 갱신은 invalid_grant(다른 기기에서 비밀번호를 바꾼 경우 등).
            let rpcBox = h.rpc
            let access = h.access
            let expiring = stage == "history" ? "message_history_with_reads" : "send_message"
            MobileStubURLProtocol.register(host: h.host) { request in
                if let name = request.rpcName {
                    if name == expiring { return BaseStub.jwtExpired }
                    return rpcBox.get()[name] ?? .missingFunction(name)
                }
                switch request.path {
                case "/auth/v1/token":
                    if request.queryValue("grant_type") == "refresh_token" { return BaseStub.invalidGrant }
                    return BaseStub.authResponse(access: access, refresh: "r1", userID: PushHarness.userID)
                case "/auth/v1/logout": return .json("{}")
                case "/rest/v1/memberships": return BaseStub.membershipOK
                default: return .missingFunction(request.path)
                }
            }
            h.clearRequests()
            let removalsBefore = h.system.deliveredRemovals

            await h.push.handleResponse(PushPayload(userInfo: PushHarness.messageUserInfo()), action: .reply("곧 갈게요"))
            #expect(!h.model.session.isSignedIn, "\(stage): 전제 — 치명 만료로 로그아웃")
            #expect(h.system.deliveredRemovals == removalsBefore + 1, "\(stage): 전제 — reset 이 알림 센터를 비웠다")
            let notice = try #require(h.system.notices.last, "\(stage): 적은 답장이 안내 없이 사라졌다")
            #expect(notice.title == PushText.replyFailedTitle)
            #expect(notice.body == PushText.replyNeedsSignIn)
            #expect(notice.userInfo["peer_id"] == PushHarness.peerID)
            let lastRemoval = try #require(h.system.events.lastIndex(of: "removeAllDelivered"))
            let lastNotice = try #require(h.system.events.lastIndex(of: "notice"))
            #expect(lastRemoval < lastNotice, "\(stage): 안내가 알림 센터 비우기보다 먼저 올라가 함께 지워진다")
            #expect(h.calls("mark_messages_read").isEmpty)
            if stage == "history" { #expect(h.calls("send_message").isEmpty) }
            #expect(h.forbiddenViolations.isEmpty)
        }
    }

    @Test("알림 설정 연달아 누르기: 저장은 한 번에 하나 · 도는 동안 '저장 중'과 마지막으로 누른 값 유지 · 끝나면 최신 값으로 한 번 더 · 최종 화면 = 마지막 서버 값")
    func overlappingPreferenceSavesAreSerialized() async throws {
        let h = PushHarness(label: "push-prefs-serial")
        h.system.status = .authorized
        defer { h.tearDown() }
        await h.launchSignedIn()
        #expect(h.push.prefs == PushPrefs(message: true, gomokuInvite: false, feedbackReply: true))

        // 앞 저장(A: message 끄기)의 응답은 늦다. 뒤 저장(B: feedback_reply 끄기)은 빠르다 — 예전에는 B 가 먼저 끝나 저장 중을 내리고
        // 늦게 온 A 응답(feedback_reply=true)이 화면 값을 덮었다.
        h.firstCallOverride.mutate {
            $0["set_push_prefs"] = .json(#"{"status":"ok","push_prefs":{"message":false,"gomoku_invite":false,"feedback_reply":true}}"#)
        }
        h.setRPC("set_push_prefs", .json(#"{"status":"ok","push_prefs":{"message":false,"gomoku_invite":false,"feedback_reply":false}}"#))
        h.clearRequests()

        // 앞 저장(A)도 뒤 저장(B)도 붙잡는다 — 응답 순서를 테스트가 정한다.
        let saveA = BaseHold.rpc("set_push_prefs", host: h.host)
        let a = Task { await h.push.setPreference(.message, enabled: false) }
        #expect(await saveA.waitHeld())
        let saveB = BaseHold.rpc("set_push_prefs", host: h.host)
        let b = Task { await h.push.setPreference(.feedbackReply, enabled: false) }
        #expect(await baseWaitUntil { !h.push.isEnabled(.feedbackReply) }, "저장 중에 새로 누른 값이 보이지 않는다")
        await h.barrier()
        #expect(saveB.held == 0, "앞 저장이 도는데 뒤 저장을 겹쳐 보냈다")
        #expect(h.push.isSavingPrefs)
        #expect(!h.push.isEnabled(.message) && !h.push.isEnabled(.feedbackReply))

        // 앞 응답이 도착한 뒤에도(뒤 저장이 아직 돈다) 화면은 마지막으로 누른 값이고 저장 중이다.
        #expect(await saveA.releaseAndWaitDelivered())
        #expect(await saveB.waitHeld())
        #expect(h.push.isSavingPrefs, "보낼 저장이 남았는데 저장 중 표시가 내려갔다")
        #expect(!h.push.isEnabled(.feedbackReply), "늦게 온 앞 응답이 뒤에 누른 값을 덮었다")
        #expect(await saveB.releaseAndWaitDelivered())

        let aResult = await a.value
        let bResult = await b.value
        #expect(aResult && bResult)
        #expect(!h.push.isSavingPrefs)
        #expect(h.push.prefsNotice == nil)
        let bodies = h.calls("set_push_prefs").map { request -> String in
            let prefs = pushBodyValue(request, "p_prefs") as? [String: Any] ?? [:]
            return "\(prefs["message"] as? Bool == true ? 1 : 0)/\(prefs["gomoku_invite"] as? Bool == true ? 1 : 0)/\(prefs["feedback_reply"] as? Bool == true ? 1 : 0)"
        }
        #expect(bodies == ["0/0/1", "0/0/0"], "둘째 저장은 두 번 누른 값을 모두 싣는다: \(bodies)")
        #expect(h.push.prefs == PushPrefs(message: false, gomokuInvite: false, feedbackReply: false))
        #expect(h.model.session.pushPrefs == PushPrefs(message: false, gomokuInvite: false, feedbackReply: false))

        // 뒤 저장이 실패하면: 안내 한 줄, 화면은 서버가 마지막으로 준 값(앞 저장 성공분)으로 돌아간다.
        h.firstCallOverride.mutate {
            $0["set_push_prefs"] = .json(#"{"status":"ok","push_prefs":{"message":true,"gomoku_invite":false,"feedback_reply":false}}"#)
        }
        h.setRPC("set_push_prefs", .networkFailure())
        h.clearRequests()
        let saveC = BaseHold.rpc("set_push_prefs", host: h.host)
        let c = Task { await h.push.setPreference(.message, enabled: true) }
        #expect(await saveC.waitHeld())
        let d = Task { await h.push.setPreference(.gomokuInvite, enabled: true) }
        #expect(await baseWaitUntil { h.push.isEnabled(.gomokuInvite) }, "저장 중에 새로 누른 값이 보이지 않는다")
        #expect(await saveC.releaseAndWaitDelivered())
        let cResult = await c.value
        let dResult = await d.value
        #expect(!cResult && !dResult)
        #expect(h.push.prefsNotice == PushText.settingsSaveFailed)
        #expect(h.push.prefs == PushPrefs(message: true, gomokuInvite: false, feedbackReply: false))
        #expect(!h.push.isSavingPrefs)
        #expect(h.forbiddenViolations.isEmpty)
    }

    @Test("답장 실패 안내를 누르면 그 대화가 열린다 · 그 대화를 보고 있어도 안내는 숨기지 않는다(서버 메시지 알림은 숨긴다)")
    func replyFailureNoticeOpensConversation() async throws {
        let h = PushHarness(label: "push-local-notice")
        h.system.status = .authorized
        defer { h.tearDown() }
        await h.launchSignedIn(active: false)
        h.setRPC("message_history_with_reads", PushHarness.historyWithReceived(id: "99999999-0000-4000-8000-000000000000"))
        await h.push.handleResponse(PushPayload(userInfo: PushHarness.messageUserInfo()), action: .reply("곧 가요"))
        let notice = try #require(h.system.notices.last)
        #expect(notice.body == PushText.replyMessageGone)

        // 알림 센터가 돌려주는 모양([AnyHashable: Any])으로 누른다.
        let delivered: [AnyHashable: Any] = Dictionary(uniqueKeysWithValues: notice.userInfo.map { (AnyHashable($0.key), $0.value as Any) })
        let tapped = try #require(PushPayload(userInfo: delivered), "안내 알림 본문을 읽지 못한다 — 눌러도 아무 화면도 열리지 않는다")
        await h.push.handleResponse(tapped, action: .open)
        #expect(h.model.router.lastOpenedRoute == .message(peerID: PushHarness.peerID))
        #expect(h.model.router.selectedTab == .messages)

        h.model.sceneDidBecomeActive()
        await h.settle()
        h.model.router.visibleConversationPeerID = PushHarness.peerID
        #expect(h.push.presentation(for: tapped) == .banner, "보고 있는 대화라도 답장 실패 안내는 보여야 한다")
        #expect(h.push.presentation(for: PushPayload(userInfo: PushHarness.messageUserInfo())) == .hidden, "대조: 서버 메시지 알림은 숨긴다")
        #expect(h.forbiddenViolations.isEmpty)
    }

    // MARK: - 데모

    @Test("데모 -AingCheckDemoPushOpen: 로그인 뒤 그 종류의 알림을 누른 경로로 연다 · 금지 호출 0")
    func demoPushOpen() async {
        for (raw, tab, route) in [
            ("message", AingTab.messages, AingRoute.message(peerID: PushDemo.peerID)),
            ("gomoku_invite", .games, .gomokuInvite(matchID: PushDemo.matchID)),
            ("feedback_reply", .me, .feedback(reportID: PushDemo.reportID)),
        ] {
            MobileStubURLProtocol.clearRequests(host: MobileDemo.host)
            let arguments = ["app", "-AingCheckDemo", "YES", "-AingCheckDemoRoute", "now", "-AingCheckDemoPushOpen", raw]
            let model = MobileAppModel(environment: MobileDemo.environment(arguments: arguments)!)
            model.push.attach(system: PushFakeSystem())
            model.installPushNotifications(arguments: arguments)
            model.start()
            #expect(await baseWaitUntil { model.router.lastOpenedRoute == route }, "\(raw): \(String(describing: model.router.lastOpenedRoute))")
            #expect(model.router.selectedTab == tab)
            #expect(PushPayload(json: PushDemo.payloadJSON(PushKind(rawValue: raw)!))?.route == route)
            await model.push.pendingStatusCheck?.value
            await model.session.pendingDeviceRegistration?.value
            await baseBarrier(model.context.service)
            #expect(MobileForbiddenCalls.violations(in: MobileStubURLProtocol.requests(host: MobileDemo.host)).isEmpty)
        }
        BaseStub.tearDown(host: MobileDemo.host, storage: .temporary(name: "demo"))
    }
}
