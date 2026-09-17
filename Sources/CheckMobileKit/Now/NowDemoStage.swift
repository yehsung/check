#if DEBUG
import Foundation

/// 데모 스크린샷용 장면(DEBUG 전용 — Release 에서 컴파일되지 않는다). 데모 라우트 `now` 위에 실행 인자로 한 장면을 더 연다:
///
///     simctl launch <기기> com.yehsung.aingcheck -AingCheckDemo YES -AingCheckDemoRoute now -AingCheckDemoNow goal|undo|edit|old|working(쉼표로 여러 개)
///
/// - goal: 주간 목표 시트 · undo: 첫 할 일을 지운 뒤 되돌리기 토스트(닫히지 않게 붙잡음) · edit: 둘째 할 일 수정 중 · old: 오래된 항목 펼침
/// - working: 지금 근무 중 절까지 스크롤
@MainActor
enum NowDemoStage {
    static let argument = "-AingCheckDemoNow"

    /// 쉼표로 여러 장면을 함께 연다(예: `old,working`).
    static func stages(arguments: [String] = ProcessInfo.processInfo.arguments) -> Set<String> {
        guard let index = arguments.firstIndex(of: argument), arguments.indices.contains(index + 1) else { return [] }
        return Set(arguments[index + 1].lowercased().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
    }

    /// 데이터가 올 때까지(최대 6초) 기다린다.
    static func waitForData(_ store: NowStore) async -> Bool {
        for _ in 0..<120 {
            if store.hasLoadedTeam, !store.todos.items.isEmpty { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }

    /// 첫 새로고침이 끝날 때까지(성공 · 실패 무관, 최대 6초). 실패 장면(픽스처를 503 으로 바꾼 빌드)에서도 스크롤이 움직이게.
    static func waitForAttempt(_ store: NowStore) async -> Bool {
        for _ in 0..<120 {
            if store.workingLoadState != .loading, !store.todos.items.isEmpty { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }

    /// 탭 화면 단 장면(시트 · 토스트).
    static func apply(store: NowStore, openGoalSheet: () -> Void) async {
        let stages = stages()
        guard store.context.isDemo, !stages.isEmpty, await waitForData(store) else { return }
        if stages.contains("goal") {
            openGoalSheet()
        }
        if stages.contains("undo") {
            store.demoHoldsUndo = true
            if let first = store.todoRows().main.first {
                store.deleteTodo(first.id)
            }
        }
    }
}
#endif
