import CheckCore
import CheckMobileShared
import Foundation

/// 위젯 체크(`ToggleTodoIntent`)의 본문 — 플랫폼 무관(macOS `swift test` 로 검증, iOS 인텐트는 이 함수 한 줄을 부른다).
///
/// 순서(SPEC-ios §4 · R5)
/// 1. App Group 할 일 파일을 **조정 구간 안에서** 코어 `TodoListStore` 로 열어 완료를 뒤집는다(앱과 같은 규칙: 정수 ms · 1ms 밀어 올리기 ·
///    pending 에 넣기 · 붙잡기 풀기). 앱의 다시 읽기·편집도 같은 URL 의 조정 구간을 쓴다(`NowTodoFileAccess`).
/// 2. 위젯 스냅샷의 그 줄 체크 표시만 고친다 — 위젯은 스냅샷만 그리므로, 이걸 안 하면 체크가 앱을 열 때까지 안 보인다.
/// 3. **토큰 갱신은 절대 하지 않는다.** 키체인 access token 이 60초 이상 유효할 때만 `todo_sync` 를 한 번 보낸다(재시도·401 갱신 없음).
///    아니면 pending 이 파일에 남아 앱이 active 가 될 때 올린다.
/// 4. 응답이 오면 다시 조정 구간에서 **그 순간의 파일**을 열어 코어 병합(`applySync` — 보낸 스냅샷 비교)으로 합친다. 그 사이 앱이
///    파일을 고쳤어도 보낸 뒤 바뀐 줄은 pending 으로 남는다.
@MainActor
package enum WidgetTodoToggle {
    /// access token 과 요청 → 응답. 프로덕션은 `SupabaseWorkService.todoSync`, 테스트는 스텁.
    package typealias Sync = @MainActor (_ accessToken: String, _ request: TodoSyncRequest) async throws -> TodoSyncResponse

    package enum Outcome: Equatable, Sendable {
        /// 로그아웃(할 일 파일 없음).
        case signedOut
        /// 그 id 가 목록에 없다(다른 기기에서 지웠고 스냅샷이 낡았다).
        case notFound
        /// 파일에는 저장했고 서버에는 못 보냈다(앱이 다음에 올린다).
        case savedLocally(SkipReason)
        case synced
    }

    package enum SkipReason: Equatable, Sendable {
        /// 토큰이 없거나 60초 안에 만료된다 — 갱신하지 않고 앱에 맡긴다.
        case tokenUnusable
        case serverMissing
        case failed
        case refused(String?)
    }

    package static func run(
        todoID: String,
        shared: WidgetSharedData,
        now: @escaping () -> Date,
        sync: Sync
    ) async -> Outcome {
        guard let url = shared.todoFileURL else { return .signedOut }
        guard let id = UUID(uuidString: todoID) else { return .notFound }

        var outgoing: TodoSyncOutgoing?
        var isDone: Bool?
        coordinated(at: url) {
            let list = TodoListStore(fileURL: url, clock: now)
            guard list.items.contains(where: { $0.id == id && $0.deletedAt == nil }) else { return }
            list.toggleDone(id)
            isDone = list.items.first { $0.id == id }?.isDone
            // 파일에 쌓인 보낼 것 전부(앱이 못 올린 변경 포함)를 한 요청에 싣는다 — 서버 상한 500.
            let pending = list.pendingIDs.sorted { $0.uuidString < $1.uuidString }
            outgoing = list.makeSyncRequest(ids: Array(pending.prefix(TodoSync.batchLimit)))
        }
        guard let isDone, let outgoing else { return .notFound }
        patchSnapshot(at: shared.storage.widgetSnapshotURL, id: id, isCompleted: isDone)

        guard let token = shared.usableAccessToken() else { return .savedLocally(.tokenUnusable) }
        let response: TodoSyncResponse
        do {
            response = try await sync(token, outgoing.request)
        } catch {
            return .savedLocally(isMissingFunction(error) ? .serverMissing : .failed)
        }
        guard let result = response.mergeableResult() else { return .savedLocally(.refused(response.status)) }
        coordinated(at: url) {
            // 새로 연 목록의 파일 세대(0)와 보낼 때의 세대(0)가 같다 — 병합 문은 코어 `applySync` 하나다.
            let list = TodoListStore(fileURL: url, clock: now)
            list.applySync(result, for: outgoing)
        }
        return .synced
    }

    /// 스냅샷의 그 줄 체크 표시만 바꾼다(순서·생성 시각은 그대로 — 앱이 다음에 새로 쓴다).
    package static func patchSnapshot(at url: URL, id: UUID, isCompleted: Bool) {
        guard var snapshot = WidgetSnapshotCodec.read(from: url) else { return }
        var changed = false
        for index in snapshot.todosPreview.indices where UUID(uuidString: snapshot.todosPreview[index].id) == id {
            if snapshot.todosPreview[index].isCompleted != isCompleted {
                snapshot.todosPreview[index].isCompleted = isCompleted
                changed = true
            }
        }
        guard changed else { return }
        try? WidgetSnapshotCodec.write(snapshot, to: url)
    }

    private static func isMissingFunction(_ error: Error) -> Bool {
        switch error as? SupabaseWorkServiceError {
        case .databaseSchemaMissing?, .invalidResponse(404)?:
            return true
        default:
            return false
        }
    }

    /// 앱(`NowTodoFileAccess`)과 같은 조정: 같은 URL 의 쓰기 조정 구간. 조정이 실패해도 한 번은 부른다.
    private static func coordinated(at url: URL, _ body: () -> Void) {
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
