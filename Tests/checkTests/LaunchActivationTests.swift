import AppKit
import Foundation
import Testing
@testable import check

// MARK: - D1: 실행 시 저장 세션 1회 킥
//
// 재현하는 사고: MenuBarExtra(.window) 의 콘텐츠 뷰는 팝오버를 처음 열기 전까지 생성되지 않는다(최소 재현 앱으로
// 실증). 저장 세션 활성화의 유일한 진입점이 CheckMenuView 의 `.task { await store.activateStoredSession() }`
// 였으므로, 로그인 항목으로 자동 실행된 앱에서 메뉴바 아이콘을 한 번도 누르지 않으면 그 실행 내내 토큰 회전·
// 팀 확정·상태 폴링·하트비트·자동 근무 시작이 전부 0회였다.
//
// 아래 테스트들은 `activateStoredSessionOnLaunch()`(= AppDelegate.applicationDidFinishLaunching 의 마지막 줄)이
// 그 구멍을 메우면서도, 요청이 나가면 **안 되는** 두 경우(비로그인 / anon 키 없음)에는 여전히 조용한지,
// 그리고 킥 뒤·킥 도중에 팝오버가 열려도 토큰 회전이 두 번 일어나지 않는지를 스텁 요청 목록으로 고정한다.

/// 실행 킥은 팝오버를 한 번도 열지 않아도 저장 세션을 활성화한다 — 토큰 회전 + 팀 확정 요청이 실제로 나간다.
@MainActor
@Test
func launchKickActivatesStoredSessionWithoutPopover() async {
    let testHost = "launch-kick-activation"
    let defaults = launchIsolatedDefaults()
    // 지난 실행이 남긴 저장 세션(팝오버를 열어야만 살아나던 그 상태).
    defaults.set("old-access-token", forKey: WorkTimerStore.accessTokenKey)
    defaults.set("old-refresh-token", forKey: WorkTimerStore.refreshTokenKey)
    defaults.set("00000000-0000-0000-0000-000000000002", forKey: WorkTimerStore.userIDKey)
    let store = launchStubStore(host: testHost, defaults: defaults)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.pokePollTask?.cancel()
    }
    #expect(store.isSignedIn)
    #expect(store.shouldActivateOnLaunch)

    // applicationDidFinishLaunching 상당 경로(팝오버 .task 는 한 번도 돌지 않는다).
    let kick = store.activateStoredSessionOnLaunch()
    #expect(kick != nil)
    await kick?.value

    // 1) 팀 확정 요청이 실제로 나갔다 — 이게 없으면 팀이 nil 로 남아 하트비트·큐 드레인·넛지가 전부 죽는다.
    let paths = URLProtocolStub.requests(forHost: testHost).compactMap { $0.url?.path }
    #expect(paths.contains("/rest/v1/memberships"))
    #expect(store.currentTeamID == URLProtocolStub.stubTeamID)
    #expect(store.membershipConfirmed)

    // 2) 저장 토큰도 회전됐다(다음 요청이 만료 토큰으로 나가지 않게).
    #expect(paths.contains("/auth/v1/token"))
    #expect(store.session?.accessToken == "refreshed-token")
    #expect(defaults.string(forKey: WorkTimerStore.accessTokenKey) == "refreshed-token")

    // 3) 상태 폴링 루프까지 기동한다 — 실행 킥의 목적은 '한 번 읽기'가 아니라 그 실행 내내 도는 것이다.
    #expect(store.refreshTask != nil)
}

/// 비로그인 실행에서는 킥이 아무 요청도 내지 않는다(로그인 화면만 떠 있는 맥에서 네트워크 0건).
@MainActor
@Test
func launchKickSendsNoRequestsWhenSignedOut() async {
    let testHost = "launch-kick-signed-out"
    // 저장 세션 없음(빈 defaults) → 복구되는 세션이 없다.
    let store = launchStubStore(host: testHost, defaults: launchIsolatedDefaults())
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.pokePollTask?.cancel()
    }
    #expect(!store.isSignedIn)

    #expect(store.shouldActivateOnLaunch == false)
    let kick = store.activateStoredSessionOnLaunch()
    #expect(kick == nil)

    // 발사할 Task 자체가 없으므로 나중에 새어 나올 요청도 없다.
    #expect(URLProtocolStub.requests(forHost: testHost).isEmpty)
    #expect(store.refreshTask == nil)
}

/// anon 키가 없으면 킥하지 않는다. 이 가드가 없으면 화면 한 번 안 보이고 저장 세션이 삭제된다 —
/// 아래에서 그 삭제를 직접 실증해 가드의 존재 이유를 고정한다.
@MainActor
@Test
func launchKickSkippedWithoutAnonKeyKeepsStoredSession() async {
    let testHost = "launch-kick-no-anon-key"
    let defaults = launchIsolatedDefaults()
    defaults.set("old-access-token", forKey: WorkTimerStore.accessTokenKey)
    defaults.set("old-refresh-token", forKey: WorkTimerStore.refreshTokenKey)
    defaults.set("00000000-0000-0000-0000-000000000002", forKey: WorkTimerStore.userIDKey)
    // 키 없이 `swift run` 한 개발 맥: 저장 세션은 살아 있지만 canSync 는 false 다.
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(testHost)")!,
        anonKey: nil,
        session: URLSession(configuration: .stubbed)
    )
    let store = WorkTimerStore(
        service: service,
        environment: [:],
        defaults: defaults,
        workspaceNotifications: nil
    )
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.pokePollTask?.cancel()
    }
    #expect(store.isSignedIn)
    #expect(store.canSync == false)

    #expect(store.shouldActivateOnLaunch == false)
    #expect(store.activateStoredSessionOnLaunch() == nil)

    // 킥이 없었으니 요청도 없고, 저장 세션은 그대로 살아 있다.
    #expect(URLProtocolStub.requests(forHost: testHost).isEmpty)
    #expect(defaults.string(forKey: WorkTimerStore.accessTokenKey) == "old-access-token")

    // 가드의 존재 이유: 같은 스토어에 활성화를 직접 태우면 refresh grant 가 missingAnonKey 로 실패하고,
    // 그건 classifyAuthError 에서 .fatal 이라 저장 세션을 조용히 지운다. 팝오버를 여는 사람만 밟던 이 경로를
    // 킥이 화면 없이 밟게 되면, 실계정 세션이 아무 안내 없이 사라진다.
    await store.activateStoredSession()
    #expect(defaults.string(forKey: WorkTimerStore.accessTokenKey) == nil)
    #expect(!store.isSignedIn)
}

/// 킥이 끝난 뒤 팝오버가 열려 `.task` 가 한 번 더 돌아도 refresh grant 는 1건뿐이다.
/// 이 멱등성이 "팝오버 `.task` 를 그대로 둔 채 앞에 킥을 하나 더 놓는다"는 이 수정의 안전 근거다 —
/// 같은 refresh token 으로 grant 를 두 번 치면 GoTrue reuse-detection 이 근무 중 강제 로그아웃을 만든다.
@MainActor
@Test
func popoverTaskAfterLaunchKickDoesNotRotateTokenTwice() async {
    let testHost = "launch-kick-idempotent"
    let defaults = launchIsolatedDefaults()
    defaults.set("old-access-token", forKey: WorkTimerStore.accessTokenKey)
    defaults.set("old-refresh-token", forKey: WorkTimerStore.refreshTokenKey)
    defaults.set("00000000-0000-0000-0000-000000000002", forKey: WorkTimerStore.userIDKey)
    let store = launchStubStore(host: testHost, defaults: defaults)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.pokePollTask?.cancel()
    }

    // 1) 실행 킥.
    await store.activateStoredSessionOnLaunch()?.value
    #expect(store.hasActivatedStoredSession)
    #expect(launchGrantCount(host: testHost) == 1)

    // 2) 사용자가 메뉴바 아이콘을 눌러 팝오버가 열린다(CheckMenuView 의 .task 상당).
    await store.activateStoredSession()

    // 회전은 여전히 1회 — fast path 는 멤버십/팀 상태만 다시 읽는다.
    #expect(launchGrantCount(host: testHost) == 1)
    #expect(store.session?.accessToken == "refreshed-token")
    #expect(defaults.string(forKey: WorkTimerStore.refreshTokenKey) == "next-refresh-token")

    // 킥이 두 번 쏘이지도 않는다(이미 활성화된 스토어는 shouldActivateOnLaunch 가 걸러 낸다).
    #expect(store.shouldActivateOnLaunch == false)
}

/// **킥이 아직 도는 중에** 팝오버가 열려도 refresh grant 는 1건뿐이다(직렬화 가드).
///
/// 위 멱등성 테스트가 덮지 못하는 진짜 위험 구간이다. 킥의 grant 가 in-flight 인 사이에 팝오버가 들어오면
/// 세션은 아직 회전 전(old-access-token)이라, 뒤따르는 confirmMembership 이 그 낡은 토큰으로 나갔다 401 을
/// 만나고, withSessionRetry 가 **킥과 같은 낡은 refresh token 으로** 두 번째 grant 를 친다. GoTrue 의
/// reuse-detection 창을 벗어나면 그 순간 근무 중에 강제 로그아웃이 된다.
/// `activateStoredSession()` 의 `await launchActivationTask.value` 한 줄을 지우면 이 단언이 2가 되어 깨진다.
@MainActor
@Test
func launchKickSerializesRefreshGrantWithPopoverOpen() async {
    // 접두어 delayed- 로 모든 응답이 지연되고(= grant in-flight 창이 실제로 열린다), 접미어 expired-token 으로
    // 낡은 access token 요청은 401 을 받는다. 두 규약을 동시에 만족하는 호스트여야 이 사고가 재현된다.
    let testHost = "delayed-expired-token"
    let defaults = launchIsolatedDefaults()
    defaults.set("old-access-token", forKey: WorkTimerStore.accessTokenKey)
    defaults.set("old-refresh-token", forKey: WorkTimerStore.refreshTokenKey)
    defaults.set("00000000-0000-0000-0000-000000000002", forKey: WorkTimerStore.userIDKey)
    let store = launchStubStore(host: testHost, defaults: defaults)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.pokePollTask?.cancel()
    }

    // 1) 실행 킥 발사 — 여기서 기다리지 않는다(응답이 지연되므로 grant 는 아직 왕복 중이다).
    let kick = store.activateStoredSessionOnLaunch()
    #expect(kick != nil)

    // 2) 그 사이에 사용자가 메뉴바 아이콘을 눌러 팝오버가 열린다.
    await store.activateStoredSession()
    await kick?.value

    // 회전은 정확히 1회. 2가 되면 같은 refresh token 을 두 번 쓴 것이다.
    #expect(launchGrantCount(host: testHost) == 1)
    #expect(store.session?.accessToken == "refreshed-token")
    #expect(store.isSignedIn)
    // 낡은 토큰으로 나간 요청이 하나도 없어야 한다(401 을 아예 만들지 않는 것이 이 가드의 목적).
    let staleAuthed = URLProtocolStub.requests(forHost: testHost).filter {
        $0.url?.path.hasPrefix("/rest/v1/") == true
            && $0.value(forHTTPHeaderField: "Authorization") == "Bearer old-access-token"
    }
    #expect(staleAuthed.isEmpty)
}

// MARK: - D1: 넛지 스케줄러 실행 시 가동

/// 오버레이 컨트롤러를 만드는 것만으로 넛지 감지가 돌기 시작한다.
///
/// 이 줄이 없으면 스케줄러의 유일한 기동 지점이 `updateWorking` 의 defer 였고, `updateWorking` 은 숨겨진
/// 패널의 SwiftUI 루트 뷰가 `.onChange(initial: true)` 를 실제로 평가해 줄 때만 불린다 — 즉 자동 근무 시작
/// 전체가 검증되지 않은 런타임 가정에 매달려 있었다. 팝오버를 한 번도 열지 않는 사용자에게 이 가정이 틀리면
/// 넛지는 영영 발동하지 않는다.
@MainActor
@Test
func overlayControllerStartsNudgeSchedulerAtLaunch() {
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: launchIsolatedDefaults(),
        workspaceNotifications: nil
    )
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "me")
    store.currentTeamID = URLProtocolStub.stubTeamID
    #expect(store.snapshot.isWorking == false)

    let controller = CheckOverlayController(
        store: store,
        notificationCenter: NotificationCenter(), // 전역 노티 오염 방지.
        defaults: launchIsolatedDefaults(),
        workspaceNotifications: nil
    )
    defer {
        // 정리: 자격을 없앤 뒤 동기화 경로를 한 번 태워 루프를 끈다.
        store.session = nil
        controller.updateWorking(false)
    }

    // 표시(근무중)로 전이한 적이 없어도 감지는 이미 돌고 있어야 한다.
    #expect(controller.shouldBeVisible == false)
    #expect(controller.nudgeSchedulerRunning)
}

/// 비로그인 실행에서는 실행 시 가동이 스케줄러를 켜지 않는다(유휴 루프 신설 금지 — 자격이 생기면 그때 켜진다).
@MainActor
@Test
func overlayControllerLeavesNudgeSchedulerOffWhenSignedOut() {
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: launchIsolatedDefaults(),
        workspaceNotifications: nil
    )
    let controller = CheckOverlayController(
        store: store,
        notificationCenter: NotificationCenter(),
        defaults: launchIsolatedDefaults(),
        workspaceNotifications: nil
    )

    #expect(!store.isSignedIn)
    #expect(controller.nudgeSchedulerRunning == false)
}

// MARK: - 헬퍼

/// refresh grant(= refresh token 회전) 요청 건수. 로그인 grant 와 구분하려 쿼리로 판별한다.
@MainActor
private func launchGrantCount(host: String) -> Int {
    URLProtocolStub.requests(forHost: host).filter {
        $0.url?.path == "/auth/v1/token" && $0.url?.query?.contains("grant_type=refresh_token") == true
    }.count
}

/// 스텁 URL 세션을 물린 스토어. 세션은 주입하지 않는다 — 이 스위트는 "defaults 에서 복구되는 저장 세션"이
/// 실행 킥의 입력이므로, 복구 경로를 그대로 태워야 한다.
@MainActor
private func launchStubStore(host: String, defaults: UserDefaults) -> WorkTimerStore {
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )
    return WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: defaults,
        // 실제 잠자기/깨어남 옵저버를 걸지 않는다(테스트 격리).
        workspaceNotifications: nil
    )
}

private func launchIsolatedDefaults() -> UserDefaults {
    let suiteName = "check-launch-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
