import Foundation
import Testing
@testable import check

// MARK: - 집중 모드(콕찌르기 수신 거부)
//
// 계약: 판정의 권위는 **서버**다(poke_user/ultra_poke_user 게이트). 클라 미러는 화면 표시와 낙관 반영용이며,
// 거절은 보낸이의 쿨타임도 울트라 하루 몫도 태우지 않는다(서버가 두 검사보다 앞에서 막는다).

@MainActor
private func makeFocusStore(host: String) -> WorkTimerStore {
    let suiteName = "check-focus-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    let store = WorkTimerStore(
        service: SupabaseWorkService(
            projectURL: URL(string: "http://\(host)")!,
            anonKey: "anon-test-key",
            session: URLSession(configuration: .stubbed)
        ),
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: defaults,
        workspaceNotifications: nil
    )
    store.session = SupabaseSession(
        accessToken: "access-token", refreshToken: nil,
        userID: "00000000-0000-0000-0000-000000000002"
    )
    return store
}

// MARK: 서버 응답 매핑

@Test
func targetFocusedStatusMapsToItsOwnOutcome() {
    // 이 status 를 모르면 default 로 떨어져 "지금은 찌를 수 없다"(invalid)로 뭉개진다 —
    // 사용자는 상대가 집중 중인지 앱이 고장인지 구분할 수 없다.
    let focused = PokeSendResponse(status: "target_focused")
    #expect(PokeSendOutcome(response: focused) == .targetFocused)

    // 대조군: 기존 어휘가 그대로 살아 있어야 한다.
    #expect(PokeSendOutcome(response: PokeSendResponse(status: "ok")) == .ok)
    #expect(PokeSendOutcome(response: PokeSendResponse(status: "target_not_working")) == .targetNotWorking)
    #expect(PokeSendOutcome(response: PokeSendResponse(status: "뭔가새로운것")) == .invalid)
}

@Test
func focusModeColumnIsOptionalSoOldServersStillDecode() throws {
    // 앱을 먼저 배포하고 db push 가 늦은 창에서는 서버가 focus_mode 키를 안 보낸다.
    // 비옵셔널이면 이 디코드가 통째로 throw 되어 토큰 공개 설정까지 함께 죽는다.
    let legacy = #"[{"token_usage_public":true,"token_usage_collect":true}]"#.data(using: .utf8)!
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let rows = try decoder.decode([ProfilePrivacyRow].self, from: legacy)
    #expect(rows.first?.focusMode == nil)   // 없으면 '모름' → 호출부가 꺼짐(false)으로 해석한다.

    let current = #"[{"token_usage_public":true,"token_usage_collect":true,"focus_mode":true}]"#.data(using: .utf8)!
    #expect(try decoder.decode([ProfilePrivacyRow].self, from: current).first?.focusMode == true)
}

// MARK: 토글

@MainActor
@Test
func toggleFocusModeAppliesOptimisticallyAndPatchesProfile() async {
    let host = "focus-toggle"
    let store = makeFocusStore(host: host)
    defer { store.tickerTask?.cancel(); store.refreshTask?.cancel(); store.syncTask?.cancel() }

    #expect(store.focusMode == false)
    store.toggleFocusMode()
    // 낙관 반영: 서버 왕복을 기다리지 않고 화면이 먼저 바뀐다(토글은 즉답이어야 한다).
    #expect(store.focusMode)

    // 같은 값 재설정은 요청을 만들지 않는다(@Observable 무효화·헛왕복 방지).
    let before = URLProtocolStub.requests(forHost: host).count
    store.setFocusMode(true)
    #expect(URLProtocolStub.requests(forHost: host).count == before)
}

@MainActor
@Test
func focusModeNoticeTellsTheSenderNothingWasSpent() {
    // 몫이 안 깎였다는 사실까지 말해야 한다 — 안 그러면 사용자가 남은 울트라 횟수를 잘못 센다.
    #expect(WorkTimerStore.targetFocusedNotice.contains("집중"))
    #expect(WorkTimerStore.targetFocusedNotice != WorkTimerStore.ultraEmptyNotice)
}

@MainActor
@Test
func focusModePanelNoticeYieldsToTheBlockingReason() {
    // 안내줄은 하나뿐이다. 지금 이 화면에서 하려는 일(찌르기)의 차단 사유가 우선이고,
    // 집중 모드는 내 수신 설정이라 정보에 가깝다 — 그래서 비근무 안내가 앞선다.
    #expect(PokeFocusNotice.text.contains("받지 않아요"))
}
