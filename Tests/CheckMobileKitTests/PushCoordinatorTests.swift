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

    @Test("앱이 뒤에 있을 때 로그인(알림으로 뒤에서 깨어남)이면 시트를 띄우지 않는다 · 데모 조립은 명시하지 않으면 시트 없음")
    func noPrimerInBackgroundOrDemo() async throws {
        let h = PushHarness()
        defer { h.tearDown() }
        await h.launchSignedIn(active: false)
        #expect(h.system.statusReads >= 1)
        #expect(!h.push.isPrimerPresented)

        MobileStubURLProtocol.clearRequests(host: MobileDemo.host)
        let environment = try #require(MobileDemo.environment(arguments: ["app", "-AingCheckDemo", "YES", "-AingCheckDemoRoute", "now"]))
        let demo = MobileAppModel(environment: environment)
        let system = PushFakeSystem()
        demo.push.attach(system: system)
        demo.session.clientReleaseTimeoutSeconds = 0   // 벽시계 상한 없음
        demo.start()
        #expect(await baseWaitUntil { demo.session.isSignedIn })
        demo.sceneDidBecomeActive()
        await demo.push.pendingStatusCheck?.value
        #expect(!demo.push.isPrimerPresented, "데모 스크린샷(다른 탭)이 시트에 가린다")

        let forced = MobileAppModel(environment: try #require(MobileDemo.environment(arguments: ["app", "-AingCheckDemo", "YES", "-AingCheckDemoRoute", "now"])))
        let forcedSystem = PushFakeSystem()
        forced.push.attach(system: forcedSystem)
        forced.applyPushDemoArguments(["app", "-AingCheckDemo", "YES", "-AingCheckDemoPushPrimer", "YES"])
        forced.session.clientReleaseTimeoutSeconds = 0
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
        #expect(h.push.presentation(for: nil) == .banner, "모르는 알림은 그대로 보인다")
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
        await h.push.handleResponse(PushPayload(userInfo: PushHarness.messageUserInfo()), action: .dismiss)
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
        #expect(MobileForbiddenCalls.violations(in: MobileStubURLProtocol.requests(host: h.host)).isEmpty)
        #expect(empty.forbiddenViolations.isEmpty)
    }

    // MARK: - 옛 카테고리 액션(w10 — 답장 · 읽음 · 거절을 걷어냈다)

    /// 이미 설치된 앱이 등록했던 카테고리의 버튼 식별자. 새 빌드가 카테고리를 다시 등록하기 전에 눌리면 이 글자로 온다.
    static let legacyActions: [(identifier: String, userInfo: [AnyHashable: Any], tab: AingTab, route: AingRoute)] = [
        ("MESSAGE_REPLY", PushHarness.messageUserInfo(), .messages, .message(peerID: PushHarness.peerID)),
        ("MESSAGE_READ", PushHarness.messageUserInfo(), .messages, .message(peerID: PushHarness.peerID)),
        ("GOMOKU_DECLINE", PushHarness.gomokuUserInfo(), .games, .gomokuInvite(matchID: PushHarness.matchID)),
    ]

    @Test("옛 알림의 답장 · 읽음 · 거절 식별자(앱이 앞): 버리지 않고 탭처럼 그 화면을 연다 · 보내기 · 읽음 · 오목 응답 요청 0 · 스토어 새로고침은 탭과 같다")
    func legacyActionIdentifiersOpenLikeTap() async throws {
        let h = PushHarness(label: "push-legacy-front")
        h.system.status = .authorized
        defer { h.tearDown() }
        h.setRPC("gomoku_inbox", PushBadgeTests.inboxEmpty)
        await h.launchSignedIn()

        for legacy in Self.legacyActions {
            h.model.router.reset()
            h.clearRequests()
            // 어댑터와 같은 길: 식별자 글자 → PushAction → 코디네이터.
            let action = PushAction(actionIdentifier: legacy.identifier)
            await h.push.handleResponse(PushPayload(userInfo: legacy.userInfo), action: action)
            #expect(h.model.router.selectedTab == legacy.tab, "\(legacy.identifier)")
            #expect(h.model.router.consumePendingRoute(for: legacy.tab) == legacy.route, "\(legacy.identifier): 탭과 같은 화면이 아니다")
            if legacy.tab == .games {
                #expect(await baseWaitUntil { !h.calls("gomoku_inbox").isEmpty }, "탭처럼 받은함을 다시 읽지 않았다")
            }
            await h.barrier()
            let names = h.requests().compactMap(\.rpcName)
            #expect(!names.contains("send_message") && !names.contains("mark_messages_read") && !names.contains("gomoku_respond"),
                    "\(legacy.identifier): 걷어낸 액션의 서버 호출이 나갔다: \(names)")
        }
        #expect(h.system.remoteUnregistrations == 0 && h.system.deliveredRemovals == 0, "옛 액션이 로그아웃 정리를 부르면 안 된다")
        #expect(h.model.session.isSignedIn)
        #expect(h.forbiddenViolations.isEmpty)
    }

    @Test("옛 알림 액션으로 **뒤에서 켜진 실행**(키체인 세션, 복원 중에 도착): 복원 뒤 그 화면을 열어 두고, 아이콘 배지는 건드리지 않는다 · 걷어낸 액션 요청 0")
    func legacyActionIdentifiersInBackgroundLaunch() async throws {
        for legacy in Self.legacyActions {
            let h = PushHarness(label: "push-legacy-back-\(legacy.identifier.lowercased())")
            h.system.status = .authorized
            defer { h.tearDown() }
            h.setRPC("client_release", .json(#"{"status":"ok","platform":"ios","min_build":1,"latest_build":1}"#))
            h.setRPC("gomoku_inbox", PushBadgeTests.inboxEmpty)
            h.setRPC("message_unread_summary", PushHarness.unreadSummary(total: 2))

            let slowRelease = BaseHold.rpc("client_release", host: h.host)
            let model = h.makeRestoredModel()
            #expect(model.session.phase == .launching)
            let response = Task { await model.push.handleResponse(PushPayload(userInfo: legacy.userInfo), action: PushAction(actionIdentifier: legacy.identifier)) }
            #expect(await slowRelease.waitHeld())
            await baseYield()
            #expect(model.session.phase == .launching, "전제: 복원이 아직 떠 있다")
            #expect(model.router.lastOpenedRoute == nil, "복원이 끝나기 전에 열었다")
            #expect(await slowRelease.releaseAndWaitDelivered())
            await response.value

            #expect(model.session.isSignedIn)
            #expect(model.router.selectedTab == legacy.tab, "\(legacy.identifier)")
            #expect(model.router.consumePendingRoute(for: legacy.tab) == legacy.route, "\(legacy.identifier)")
            await baseBarrier(model.context.service)
            await baseYield()
            #expect(h.system.badgeCounts.isEmpty, "\(legacy.identifier): 앱이 앞에 오기 전에 배지를 적었다: \(h.system.badgeCounts)")
            #expect(model.push.badgeState == .unknown)
            let names = h.requests().compactMap(\.rpcName)
            #expect(!names.contains("send_message") && !names.contains("mark_messages_read") && !names.contains("gomoku_respond"),
                    "\(legacy.identifier): \(names)")
            #expect(h.forbiddenViolations.isEmpty)
        }
    }

    // MARK: - 오목 수락

    @Test("수락: gomoku_respond(accept) → 판이 열리면 대국으로 · 만료면 신청 화면으로 · 오목이 아닌 알림의 수락은 탭처럼 그 화면")
    func gomokuAccept() async throws {
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

        // 카테고리와 맞지 않는 수락(서버·앱 버전이 어긋남): 오목 응답 없이 탭처럼 그 알림의 화면.
        expired.clearRequests()
        expired.model.router.reset()
        await expired.push.handleResponse(PushPayload(userInfo: PushHarness.messageUserInfo()), action: .acceptInvite)
        #expect(expired.calls("gomoku_respond").isEmpty)
        #expect(expired.model.router.lastOpenedRoute == .message(peerID: PushHarness.peerID))
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

    // MARK: - 데모

    @Test("데모 -AingCheckDemoPushOpen: 로그인 뒤 그 종류의 알림을 누른 경로로 연다 · 금지 호출 0")
    func demoPushOpen() async throws {
        for (raw, tab, route) in [
            ("message", AingTab.messages, AingRoute.message(peerID: PushDemo.peerID)),
            ("gomoku_invite", .games, .gomokuInvite(matchID: PushDemo.matchID)),
            ("feedback_reply", .me, .feedback(reportID: PushDemo.reportID)),
        ] {
            MobileStubURLProtocol.clearRequests(host: MobileDemo.host)
            let arguments = ["app", "-AingCheckDemo", "YES", "-AingCheckDemoRoute", "now", "-AingCheckDemoPushOpen", raw]
            let model = MobileAppModel(environment: try #require(MobileDemo.environment(arguments: arguments)))
            // 알림 열기는 실행 복원을 벽시계 상한(기본 10초)까지 기다린다 — 포화에서 먼저 지나 라우트를 안 여는 갈래로 새지 않게.
            model.push.sessionSettleTimeoutSeconds = BaseStub.patientSeconds
            model.session.clientReleaseTimeoutSeconds = 0
            model.push.attach(system: PushFakeSystem())
            model.installPushNotifications(arguments: arguments)
            model.start()
            #expect(await baseWaitUntil { model.router.lastOpenedRoute == route }, "\(raw): \(String(describing: model.router.lastOpenedRoute))")
            #expect(model.router.selectedTab == tab)
            #expect(PushPayload(json: PushDemo.payloadJSON(try #require(PushKind(rawValue: raw))))?.route == route)
            await model.push.pendingStatusCheck?.value
            await model.session.pendingDeviceRegistration?.value
            await baseBarrier(model.context.service)
            #expect(MobileForbiddenCalls.violations(in: MobileStubURLProtocol.requests(host: MobileDemo.host)).isEmpty)
        }
        BaseStub.tearDown(host: MobileDemo.host, storage: .temporary(name: "demo"))
    }
}
