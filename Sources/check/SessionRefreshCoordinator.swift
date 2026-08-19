import Foundation

/// 세션 갱신의 **단일 주체**. refresh token 회전을 부르는 곳이 둘 이상이면 GoTrue 의 reuse-detection 이
/// 한쪽을 무효로 만들고, 그 결과가 **근무 중 강제 로그아웃**이다(WorkTimerStore.swift:177-182 가 기록한 사고).
///
/// 지금(v0.2.33)은 주체가 `withSessionRetry` 하나뿐이라 경합이 없다. v0.2.34 가 리얼타임 선제 갱신을
/// 붙이는 순간 주체가 둘이 되므로, **그 전에** 이 조정자를 심어 두 경로가 같은 문을 지나게 한다.
///
/// ── 설계상 중요한 두 가지 ──
/// ① **refreshToken 을 인자로 받지 않는다.** 호출 시점에 tokenProvider 로 읽는다. 인자로 받으면
///    '동시 호출'은 막아도 **'낡은 토큰의 순차 재사용'** 을 못 막는다 — withSessionRetry 는 진입 시점에
///    currentSession 을 붙잡으므로(WorkTimerStoreAuth.swift), 앞선 갱신이 끝난 뒤 도착한 두 번째 호출이
///    이미 회전된 옛 토큰을 들고 온다. 그걸 그대로 쓰면 reuse-detection 이 터진다.
/// ② **결과를 스토어에 쓰는 책임도 여기 하나다.** 두 주체가 각자 쓰면 늦게 끝난 쪽이 낡은 토큰으로
///    되돌려 놓는다(그 뒤 모든 요청이 401 → 강제 로그아웃).
@MainActor
final class SessionRefreshCoordinator {
    /// 진행 중인 갱신. 있으면 새로 만들지 않고 **그 결과를 함께 기다린다**(합류).
    private var inFlight: Task<SupabaseSession, Error>?
    /// 그 갱신이 속한 세션 세대. 로그아웃/계정 전환으로 세대가 바뀌면 합류하지 않는다 —
    /// 앞 계정의 갱신 결과를 새 계정 세션에 쓰면 남의 토큰으로 근무를 기록한다.
    private var inFlightGeneration = -1
    /// 이 조정자를 **실제로 통과한** 갱신 횟수(성공만 센다). 진단값이자 계약의 증거다 —
    /// 이 수가 늘지 않는데 세션이 갱신됐다면 누군가 조정자를 우회해 service.refreshSession 을 직접 부른 것이고,
    /// 그게 곧 refresh token 회전 경합의 조건이다(그 상태는 갱신 주체가 둘이 되기 전까지 **증상이 없다**).
    private(set) var completedRefreshCount = 0

    init() {}

    /// 갱신을 1회로 접는다. 같은 세대의 동시 호출은 전부 같은 Task 를 기다린다.
    ///
    /// - Parameters:
    ///   - generation: 호출 시점의 sessionGeneration.
    ///   - tokenProvider: **호출 시점에** refresh token 을 읽는 클로저(위 ① 참조).
    ///   - refresh: 실제 갱신 수행(서비스 호출). 주입이라 테스트가 요청 수를 셀 수 있다.
    ///   - apply: 갱신 결과를 스토어에 반영(위 ② 참조). 성공 시 **정확히 한 번** 불린다.
    func refresh(
        generation: Int,
        tokenProvider: @MainActor () -> String?,
        refresh: @escaping @MainActor (String) async throws -> SupabaseSession,
        apply: @escaping @MainActor (SupabaseSession) -> Void
    ) async throws -> SupabaseSession {
        if let inFlight, inFlightGeneration == generation {
            return try await inFlight.value
        }
        guard let token = tokenProvider() else {
            throw SupabaseWorkServiceError.sessionExpired
        }
        let task = Task { @MainActor () throws -> SupabaseSession in
            let session = try await refresh(token)
            apply(session)
            self.completedRefreshCount += 1
            return session
        }
        inFlight = task
        inFlightGeneration = generation
        // ★ defer 를 쓰지 않는다. defer 는 스코프 종료 시점이라, 이 함수가 await 중인 동안
        //   합류한 다른 호출이 끝나도 슬롯이 안 비고, 반대로 스코프를 빠져나가는 순서에 따라
        //   **성공한 갱신의 슬롯을 실패한 호출이 지우는** 창이 생긴다. 명시적으로 비운다.
        do {
            let session = try await task.value
            clearIfCurrent(task)
            return session
        } catch {
            clearIfCurrent(task)
            throw error
        }
    }

    /// 로그아웃/계정 전환 시 호출. 진행 중 갱신의 결과가 새 세션에 적용되지 않게 슬롯을 끊는다.
    /// Task 자체는 취소하지 않는다 — 취소해도 서버 쪽 회전은 이미 일어났을 수 있고,
    /// 여기서 중요한 것은 '그 결과를 쓰지 않는 것'이다.
    func invalidate() {
        inFlight = nil
        inFlightGeneration = -1
    }

    private func clearIfCurrent(_ task: Task<SupabaseSession, Error>) {
        if inFlight == task { inFlight = nil; inFlightGeneration = -1 }
    }
}
