import CheckCore
import CheckMobileShared
import Foundation

// 지금 탭 할 일의 배선 부품: 전송(`todo_sync` ↔ 폰 세션) · 멈출 수 있는 타이머 · 파일 조정.
// 코어 `TodoListStore`·`TodoSync`·`TodoRules` 는 **그대로** 쓴다(SPEC-ios §3.2) — 여기는 폰에 맞춘 꽂는 자리만 있다.

// MARK: - 전송

/// 폰 전송: 폰 세션으로 PostgREST `todo_sync` 를 부른다. 관용구는 맥 전송과 같다 — **세션 가드 → 세대 캡처 → 401 재시도 → 세대 가드.**
/// - HTTP 200 의 `{"status":"unauthorized"}` 도 `.sessionExpired` 로 접어 세션 조정자 경유 갱신 1회를 탄다.
/// - 함수가 없는 서버(404 · PGRST202)는 `.functionMissing` — 엔진이 조용히 멈추고 pending 을 둔다.
/// - 요청한 계정이 지금 세션이 아니면 보내지 않는다(`.accountMismatch`) — 앞 계정의 할 일이 새 계정 토큰으로 올라가면 안 된다.
@MainActor
package final class NowTodoSyncTransport: TodoSyncTransport {
    private let context: MobileContext

    package init(context: MobileContext) {
        self.context = context
    }

    package func todoSync(userID: String, request: TodoSyncRequest) async throws -> TodoSyncResponse {
        guard context.session.isSignedIn, let current = context.session.session, current.userID == userID else {
            throw TodoSyncTransportError.accountMismatch
        }
        let generation = context.generation
        let service = context.service
        let response: TodoSyncResponse
        do {
            response = try await context.withMobileSessionRetry { session in
                let reply = try await service.todoSync(accessToken: session.accessToken, request: request)
                if reply.status == "unauthorized" { throw SupabaseWorkServiceError.sessionExpired }
                return reply
            }
        } catch let error where MobileDeviceRPC.isMissingFunction(error) {
            throw TodoSyncTransportError.functionMissing
        }
        guard generation == context.generation else { throw TodoSyncTransportError.accountMismatch }
        return response
    }
}

// MARK: - 타이머

/// 프로덕션 타이머(Task.sleep). 코어 `TodoSyncTaskScheduler` 와 같은 동작이다(그쪽 init 은 모듈 밖에서 부를 수 없다).
/// 취소 검사가 없으면 cancel() 이 곧 즉시 실행이 된다.
@MainActor
package final class NowTaskScheduler: TodoSyncScheduler {
    private final class Handle: TodoSyncCancellable {
        let task: Task<Void, Never>
        init(_ task: Task<Void, Never>) { self.task = task }
        func cancel() { task.cancel() }
    }

    package init() {}

    package func schedule(after seconds: Double, _ action: @escaping @MainActor () -> Void) -> any TodoSyncCancellable {
        Handle(Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            action()
        })
    }
}

// MARK: - 멈출 수 있는 타이머

/// 코어 동기화 엔진의 디바운스(1.5초)·주기(5분) 예약을 **앱이 background 인 동안 막는다**(SPEC-ios §3: background 로 가면 멈춘다).
///
/// 엔진에는 "멈춤" 문이 없다. 계정을 비우는 `activate(userID: nil)` 로 멈추면 background 직전에 띄운 마지막 전송까지 첫 줄에서
/// 돌아간다(엔진이 userID 를 다시 읽는다). 그래서 예약만 가로막는다: 멈춘 동안 깨어난 예약은 버린다 — 주기 사슬은 끊기고,
/// active 로 돌아오면 스토어가 `activate(userID:)` 로 다시 건다(그 호출이 곧바로 한 번 맞춘다).
@MainActor
package final class NowPausableScheduler: TodoSyncScheduler {
    private let base: any TodoSyncScheduler
    package private(set) var isPaused = false
    /// 멈춘 동안 버린 예약 수(테스트).
    package private(set) var droppedCount = 0

    package init(base: any TodoSyncScheduler) {
        self.base = base
    }

    package func pause() { isPaused = true }
    package func resume() { isPaused = false }

    package func schedule(after seconds: Double, _ action: @escaping @MainActor () -> Void) -> any TodoSyncCancellable {
        base.schedule(after: seconds) { [weak self] in
            guard let self else { return }
            guard !self.isPaused else {
                self.droppedCount += 1
                return
            }
            action()
        }
    }
}

// MARK: - 파일 조정

/// 앱 쪽 할 일 파일 접근을 **위젯 인텐트와 같은 조정 구간**에 넣는다(`TodoSharedFile` 과 같은 NSFileCoordinator 규칙).
///
/// 코어 `TodoListStore` 는 변경마다 파일 전체를 원자적으로 다시 쓰지만 조정자를 모른다. 위젯의 체크(`ToggleTodoIntent`)는
/// 조정 구간 안에서 읽고-고치고-쓰므로, 앱의 다시 읽기·사용자 변경을 같은 URL 의 쓰기 조정 안에서 하면 둘이 직렬화된다
/// (앱이 위젯 쓰기 사이에 끼어 읽은 옛 목록으로 위젯의 체크를 덮지 않게). 동기화 응답 병합(`applySync`)은 코어 엔진 안이라
/// 여기로 감쌀 수 없다 — 그 창은 앱이 active 이거나 background 로 막 넘어간 몇 초뿐이다(보고서 남은 위험).
package enum NowTodoFileAccess {
    /// 조정 쓰기 구간에서 `body` 를 부른다. 조정이 실패해도(드문 파일 시스템 오류) `body` 는 한 번 부른다 — 메모리가 진실이다.
    @MainActor
    package static func coordinated(at url: URL, _ body: () -> Void) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var ran = false
        var error: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: [.forMerging], error: &error) { _ in
            ran = true
            body()
        }
        if !ran { body() }
    }
}
