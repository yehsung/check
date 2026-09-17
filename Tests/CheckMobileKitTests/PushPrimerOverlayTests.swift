import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

/// 설명 시트 × 시스템 "암호를 저장하겠습니까?" 창(w6 — 운영 e2e 결함 3).
///
/// 실측(iOS 27 시뮬레이터): 그 창은 앱 프로세스의 텍스트 효과 창에 붙는 원격 모달이고, 앱 상태 · scenePhase · 키 윈도를 바꾸지 않는다.
/// 폼이 사라진 0.1~0.2초 뒤 요청되어 0.4초(원격 서비스가 떠 있음) ~ 2.2초(처음 띄움) 뒤에 나타났다. 그래서 코디네이터는
/// ① 폼 로그인 직후에만 유예를 두고 ② 창이 떠 있는 동안은 미루고 ③ 유예보다 늦게 뜬 창은 시트를 거둬들였다가 다시 띄운다.
/// 가짜 시스템의 `setSystemOverlay` 가 어댑터의 창 관찰을 대신한다. **벽시계 잠 없음** — 유예 잠은 문(`BaseGate`)으로 바꾼다.
@MainActor
@Suite(.serialized) struct PushPrimerOverlayTests {
    private static let email = "push@aing-check.invalid"

    /// 실제 순서: 앱이 앞(로그인 화면) → 폼 제출 → 로그인 상태(스토어 활성화 → 설명 시트 판정).
    private func signInFromForm(_ h: PushHarness, grace: BaseGate?) async {
        if let grace {
            h.push.credentialPromptGraceSleep = { _ in await grace.wait() }
        }
        h.push.attach(system: h.system)
        h.model.start()
        _ = await baseWaitUntil { h.model.session.phase == .signedOut }
        h.model.sceneDidBecomeActive()
        await h.model.session.signIn(email: Self.email, password: "pw")
    }

    private func cooldownRecorded(_ h: PushHarness) -> Bool {
        h.storage.defaults.object(forKey: PushCoordinator.primerDismissedAtKey) != nil
    }

    @Test("폼 로그인 직후: 유예 동안 시트를 안 띄우고, 그 사이 뜬 암호 저장 창이 **사라진 뒤에** 띄운다 · 7일 쉼 없음 · 허락 → 등록")
    func formSignInWaitsForPasswordPrompt() async {
        let h = PushHarness(label: "primer-overlay-wait")
        defer { h.tearDown() }
        let grace = BaseGate()
        await signInFromForm(h, grace: grace)
        #expect(h.model.session.signedInViaForm)
        #expect(await baseWaitUntil { h.push.primerDeferralState == .credentialPromptGrace && grace.arrivals == 1 }, "폼 로그인 뒤 유예가 서지 않았다")
        #expect(!h.push.isPrimerPresented)
        #expect(h.system.primerPresentations == 0, "유예 중에 시트를 띄웠다")
        #expect(h.system.isObservingOverlay, "유예 중에 창 관찰을 켜지 않았다")

        // 창이 떴다 — 유예는 할 일을 마쳤다. 늦게 끝난 잠은 아무것도 하지 않는다.
        let sleeping = h.push.pendingCredentialPromptGrace
        h.system.setSystemOverlay(true)
        #expect(h.push.primerDeferralState == .systemOverlay)
        #expect(h.push.pendingCredentialPromptGrace == nil)
        grace.open()
        await sleeping?.value
        await h.settle()
        await h.barrier()
        #expect(!h.push.isPrimerPresented, "암호 저장 창이 떠 있는데 시트를 띄웠다")
        #expect(h.system.primerPresentations == 0)

        // 창이 사라졌다 → 그때 띄운다.
        h.system.setSystemOverlay(false)
        #expect(await baseWaitUntil { h.push.isPrimerPresented }, "창이 끝났는데 시트가 안 떴다")
        #expect(h.system.primerPresentations == 1)
        #expect(h.push.primerDeferralState == nil)
        #expect(!cooldownRecorded(h), "사용자가 고르지 않았는데 7일 쉼을 적었다")

        await h.push.primerAllow()
        await h.settle()
        #expect(h.system.authorizationRequests == 1)
        #expect(h.system.remoteRegistrations == 1)
        #expect(!h.system.isObservingOverlay, "시트가 끝났는데 창 관찰이 남았다")
        #expect(!cooldownRecorded(h))
        #expect(h.forbiddenViolations.isEmpty)
    }

    @Test("폼 로그인 · 창이 끝내 안 뜸: 유예가 끝나야 한 번 띄운다")
    func formSignInWithoutPromptPresentsAfterGrace() async {
        let h = PushHarness(label: "primer-overlay-noprompt")
        defer { h.tearDown() }
        let grace = BaseGate()
        await signInFromForm(h, grace: grace)
        #expect(await baseWaitUntil { h.push.primerDeferralState == .credentialPromptGrace && grace.arrivals == 1 })
        await h.barrier()
        #expect(!h.push.isPrimerPresented)
        #expect(h.system.primerPresentations == 0)

        let sleeping = h.push.pendingCredentialPromptGrace
        grace.open()
        await sleeping?.value
        await h.settle()
        #expect(h.push.isPrimerPresented)
        #expect(h.system.primerPresentations == 1)
        #expect(grace.arrivals == 1, "유예를 두 번 걸었다")
        #expect(h.system.isObservingOverlay, "시트가 떠 있는 동안 늦게 뜨는 창을 보지 않는다")
        #expect(!cooldownRecorded(h))
        #expect(h.forbiddenViolations.isEmpty)
    }

    @Test("유예보다 늦게 뜬 창: 떠 있는 시트를 거둬들이고(7일 쉼 없음) 창이 끝나면 다시 띄운다 · '나중에'만 7일 쉼 · 못 띄움도 안 적는다")
    func latePromptWithdrawsAndRepresentsPrimer() async {
        let h = PushHarness(label: "primer-overlay-late")
        defer { h.tearDown() }
        await signInFromForm(h, grace: nil)   // 유예는 곧바로 끝난다(창이 늦다)
        await h.settle()
        #expect(h.push.isPrimerPresented)
        #expect(h.system.primerPresentations == 1)

        h.system.setSystemOverlay(true)
        #expect(!h.push.isPrimerPresented, "창 아래에 깔린 시트를 그대로 뒀다")
        #expect(h.system.primerDismissals == 1)
        #expect(h.push.primerDeferralState == .systemOverlay)
        // 어댑터는 코드로 내린 시트에 끌어내림 콜백을 주지 않지만, 오더라도 적지 않는다(이미 거둬들인 시트).
        h.push.primerDidDisappear()
        #expect(!cooldownRecorded(h), "시스템 창 때문에 거둬들인 시트에 7일 쉼을 적었다")
        #expect(h.system.isObservingOverlay)

        h.system.setSystemOverlay(false)
        #expect(await baseWaitUntil { h.push.isPrimerPresented }, "창이 끝났는데 시트를 다시 띄우지 않았다")
        #expect(h.system.primerPresentations == 2)
        #expect(!cooldownRecorded(h))

        // 못 띄움(presenter 없음)은 적지 않는다.
        h.push.primerCouldNotPresent()
        #expect(!h.push.isPrimerPresented)
        #expect(!cooldownRecorded(h))
        #expect(!h.system.isObservingOverlay)

        // 대조: 사용자가 누른 "나중에"는 적는다.
        h.model.sceneDidEnterBackground()
        h.model.sceneDidBecomeActive()
        await h.settle()
        #expect(h.push.isPrimerPresented)
        #expect(h.system.primerPresentations == 3)
        h.push.primerLater()
        #expect(cooldownRecorded(h))
        #expect(!h.system.isObservingOverlay)
        #expect(h.forbiddenViolations.isEmpty)
    }

    @Test("실행 복원(키체인 세션)은 유예 없이 곧바로 띄운다 · 그때 창이 떠 있으면 사라진 뒤에")
    func restoredLaunchPresentsImmediately() async {
        let h = PushHarness(label: "primer-overlay-restore")
        defer { h.tearDown() }
        let grace = BaseGate()
        let restored = h.makeRestoredModel()
        restored.push.credentialPromptGraceSleep = { _ in await grace.wait() }
        #expect(await baseWaitUntil { restored.session.isSignedIn })
        #expect(!restored.session.signedInViaForm)
        restored.sceneDidBecomeActive()
        #expect(await baseWaitUntil { restored.push.isPrimerPresented }, "복원 실행에서 시트가 곧바로 안 떴다")
        #expect(grace.arrivals == 0, "암호 창이 없는 복원 실행에 유예를 걸었다")
        #expect(h.system.primerPresentations == 1)

        // 실행 복원 때 시스템 화면이 이미 떠 있으면 미뤘다가 사라지면 띄운다 — 유예는 없다.
        let second = PushHarness(label: "primer-overlay-restore-2")
        defer { second.tearDown() }
        let secondGrace = BaseGate()
        let restoredAgain = second.makeRestoredModel()
        restoredAgain.push.credentialPromptGraceSleep = { _ in await secondGrace.wait() }
        #expect(await baseWaitUntil { restoredAgain.session.isSignedIn })
        second.system.setSystemOverlay(true)
        restoredAgain.sceneDidBecomeActive()
        #expect(await baseWaitUntil { restoredAgain.push.primerDeferralState == .systemOverlay })
        await restoredAgain.push.pendingStatusCheck?.value
        #expect(!restoredAgain.push.isPrimerPresented)
        #expect(second.system.isObservingOverlay)
        second.system.setSystemOverlay(false)
        #expect(await baseWaitUntil { restoredAgain.push.isPrimerPresented })
        #expect(secondGrace.arrivals == 0)
        #expect(second.system.primerPresentations == 1)
        #expect(h.forbiddenViolations.isEmpty)
        #expect(second.forbiddenViolations.isEmpty)
    }

    @Test("닫힌 앱: 유예 중 뒤로 가면 유예 · 관찰을 멈추고 늦은 잠이 시트를 안 띄운다 · 다시 앞에 오면 유예 없이 판정(창이 있으면 끝난 뒤)")
    func backgroundStopsWaiting() async {
        let h = PushHarness(label: "primer-overlay-background")
        defer { h.tearDown() }
        let grace = BaseGate()
        await signInFromForm(h, grace: grace)
        #expect(await baseWaitUntil { h.push.primerDeferralState == .credentialPromptGrace && grace.arrivals == 1 })
        let sleeping = h.push.pendingCredentialPromptGrace

        h.model.sceneDidEnterBackground()
        #expect(h.push.primerDeferralState == nil)
        #expect(h.push.pendingCredentialPromptGrace == nil)
        #expect(!h.system.isObservingOverlay, "닫힌 앱에서 창 관찰이 돈다")
        #expect(!h.push.isObservingSystemOverlayState)
        grace.open()
        await sleeping?.value
        await h.barrier()
        #expect(!h.push.isPrimerPresented, "뒤로 간 뒤 끝난 잠이 시트를 띄웠다")
        #expect(h.system.primerPresentations == 0)
        // 닫힌 동안의 창 신호는 받지 않는다.
        h.system.setSystemOverlay(true)
        #expect(h.push.primerDeferralState == nil)

        // 창이 떠 있는 채 앞으로 → 미룸 → 창이 끝나면 띄움. 로그인 유예는 다시 걸지 않는다.
        h.model.sceneDidBecomeActive()
        await h.settle()
        #expect(h.push.primerDeferralState == .systemOverlay)
        #expect(!h.push.isPrimerPresented)
        h.system.setSystemOverlay(false)
        #expect(await baseWaitUntil { h.push.isPrimerPresented })
        #expect(grace.arrivals == 1, "앞으로 돌아왔는데 로그인 유예를 다시 걸었다")
        #expect(h.system.primerPresentations == 1)
        #expect(!cooldownRecorded(h))
        #expect(h.forbiddenViolations.isEmpty)
    }

    @Test("로그아웃(세대) 뒤: 앞 세대의 늦게 끝난 유예는 로그인 화면에도, **다시 로그인한 뒤의 새 유예 중에도** 시트를 안 띄운다 · 새 유예는 자기 문만 따른다")
    func signOutDropsLateGrace() async {
        let h = PushHarness(label: "primer-overlay-signout")
        defer { h.tearDown() }
        let first = BaseGate()
        await signInFromForm(h, grace: first)
        #expect(await baseWaitUntil { h.push.primerDeferralState == .credentialPromptGrace && first.arrivals == 1 })
        let staleSleep = h.push.pendingCredentialPromptGrace
        let generation = h.model.session.generation

        await h.model.session.signOut()
        #expect(h.model.session.generation == generation + 1)
        #expect(h.push.primerDeferralState == nil)
        #expect(h.push.pendingCredentialPromptGrace == nil)
        #expect(!h.system.isObservingOverlay, "로그아웃 뒤에 창 관찰이 남았다")
        // 로그인 화면에서의 창 신호는 받지 않는다.
        h.system.setSystemOverlay(true)
        h.system.setSystemOverlay(false)
        await h.barrier()
        #expect(!h.push.isPrimerPresented)

        // 같은 폰에서 다시 폼 로그인 — 새 세대의 유예가 선 **뒤에** 앞 세대의 잠이 끝난다(표지 · 세대로 걸러져야 한다).
        let second = BaseGate()
        h.push.credentialPromptGraceSleep = { _ in await second.wait() }
        await h.model.session.signIn(email: Self.email, password: "pw")
        #expect(await baseWaitUntil { h.push.primerDeferralState == .credentialPromptGrace && second.arrivals == 1 })
        let currentSleep = h.push.pendingCredentialPromptGrace
        first.open()
        await staleSleep?.value
        await h.push.pendingStatusCheck?.value
        await h.barrier()
        #expect(!h.push.isPrimerPresented, "앞 세대의 늦은 유예가 새 로그인의 유예를 끊고 시트를 띄웠다(암호 창과 겹칠 수 있다)")
        #expect(h.system.primerPresentations == 0)
        #expect(h.push.primerDeferralState == .credentialPromptGrace, "앞 세대의 늦은 유예가 새 유예 상태를 지웠다")
        #expect(h.push.pendingCredentialPromptGrace != nil)

        second.open()
        await currentSleep?.value
        await h.settle()
        #expect(h.push.isPrimerPresented)
        #expect(h.system.primerPresentations == 1)
        #expect(!cooldownRecorded(h))
        #expect(h.forbiddenViolations.isEmpty)
    }
}
