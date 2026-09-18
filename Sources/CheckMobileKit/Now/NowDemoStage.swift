#if DEBUG
import Foundation

/// 데모 스크린샷용 장면(DEBUG 전용 — Release 에서 컴파일되지 않는다). 데모 라우트 `now` 위에 실행 인자로 한 장면을 더 연다:
///
///     simctl launch <기기> com.yehsung.aingcheck -AingCheckDemo YES -AingCheckDemoRoute now -AingCheckDemoNow goal|undo|edit|old|working(쉼표로 여러 개)
///
/// - goal: 주간 목표 시트 · undo: 첫 할 일을 지운 뒤 되돌리기 토스트(닫히지 않게 붙잡음) · edit: 둘째 할 일 수정 중 · old: 오래된 항목 펼침
/// - working: 지금 근무 중 절까지 스크롤
///
/// 무소속 합류 카드(라우트 `now/teamless` — 소속 픽스처가 빈 배열이다):
///
///     simctl launch <기기> com.yehsung.aingcheck -AingCheckDemo YES -AingCheckDemoRoute now/teamless -AingCheckDemoNow teamjoin|teamcreate
///
/// - teamjoin: 팀 코드를 채우고 미리보기("팀 아잉 데모팀 · 6명 · 주 40시간")까지 · teamcreate: 팀 만들기 칸(이름 · 주간 목표)
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

    /// 무소속(팀 없음)으로 설 때까지. 합류 카드 장면은 팀 상태·할 일이 오지 않으므로 `waitForData` 를 못 쓴다.
    static func waitForTeamless(_ store: NowStore) async -> Bool {
        for _ in 0..<120 {
            if store.hasNoTeam { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }

    /// 탭 화면 단 장면(시트 · 토스트 · 무소속 합류 카드).
    static func apply(store: NowStore, openGoalSheet: () -> Void) async {
        let stages = stages()
        guard store.context.isDemo, !stages.isEmpty else { return }
        if stages.contains("teamjoin") || stages.contains("teamcreate") {
            await applyTeamJoin(store: store, stages: stages)
            return
        }
        guard await waitForData(store) else { return }
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

    /// 무소속 합류 카드를 채운다(앱스토어 스크린샷). 합류·생성 **왕복은 내지 않는다** — 카드가 화면에 남아 있어야 찍는다.
    private static func applyTeamJoin(store: NowStore, stages: Set<String>) async {
        guard await waitForTeamless(store) else { return }
        let join = store.teamJoin
        if stages.contains("teamcreate") {
            join.toggleCreateTeamMode()
            join.form.createTeamName = "새벽 러너스"
            join.form.createTeamGoalHours = 50
            return
        }
        join.form.teamCode = "AING7K2Q"
        await join.form.previewTeamCode().value
    }
}
#endif
