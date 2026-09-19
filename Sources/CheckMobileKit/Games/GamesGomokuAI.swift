import CheckCore
import Foundation

// 폰 AI 오목(1.0.1) — **규칙·판·서버 차단은 전부 코어**(`GomokuStoreAI` · `GomokuAIGame` · `GomokuAI`, 맥 0.3.32 와 한 벌)이고,
// 이 파일은 폰이 코어에 끼우는 두 가지만 가진다. 플랫폼 무관(macOS `swift test` 가 검증한다).
//
// 1. `GamesGomokuAIThinker` — 코어 스토어의 AI 수 선택기 자리(`GomokuStore.aiMoveChooser`, 원래 테스트 주입점)에 끼우는 폰 선택기.
//    코어 기본 선택기(`GomokuAIRuntime.engineChooser`)와 같은 엔진을 같은 방식(분리된 백그라운드 작업)으로 부르되, 폰에만 있는
//    수명을 하나 더 안다: **오목 화면이 보이고 앱이 active 일 때만 생각한다.** 화면을 떠나거나 앱이 background 로 가면 도는 탐색을
//    취소하고(엔진의 `isCancelled`), 돌아오면 **처음부터 다시** 생각한다.
// 2. `GomokuPhoneMatchChrome` — 대국·결과 화면이 판 종류(사람 · AI)에 따라 세우는 것의 표. 사람 판 값은 w15 그대로다.
//
// ── 왜 코어를 고치지 않고 선택기를 갈아 끼우나 ──
// 코어는 맥과 같은 파일이다. 맥은 창이 닫혀도 AI 가 계속 생각하고(사람 시계만 멈춘다) 그 동작이 V0332 테스트로 못 박혀 있다.
// 취소를 코어에 넣으면 맥 동작이 바뀐다. 선택기는 코어가 일부러 열어 둔 문(`package var aiMoveChooser`)이라 맥은 한 글자도 안 바뀐다.
//
// ── 취소가 "약한 수"가 되지 않게 ──
// 엔진은 취소되면 **지금까지 찾은 최선**(없으면 첫 합법 수)을 곧바로 돌려준다(`GomokuAI.bestMove` 계약). 그 수를 코어에 넘기면
// 화면을 잠깐 떠났을 뿐인데 AI 가 덜 생각한 수를 둔다. 그래서 떠나서 끊긴 탐색의 결과는 **버리고**, 코어가 기다리는 선택기 호출은
// 돌아올 때까지 붙잡아 둔다(AI 차례에는 사람 시계가 없고, 코어는 선택기가 돌려줄 때까지 "생각 중"을 그대로 보인다).
// 코어가 자기 작업을 취소하면(기권 뒤 새 판 · 1:1 판이 열림 · 로그아웃) 붙잡은 호출은 곧바로 nil 로 풀린다 — 코어는 그 결과를
// 세대·판 id·기록 수로 이미 버린다(`scheduleAITurnIfNeeded`).

/// 폰 AI 수 선택기. 코어 `GomokuStore.aiMoveChooser` 에 `chooser` 를 끼운다(`GamesStore.init`).
@MainActor
package final class GamesGomokuAIThinker {
    /// 엔진 한 번: 판 · 둘 색 · 한도 · 취소 문 → 수. 테스트가 결정적 가짜로 갈아 끼운다.
    package typealias Engine = @Sendable (GomokuBoard, GomokuColor, GomokuAISearchLimits, @escaping @Sendable () -> Bool) -> GomokuPoint?

    /// 폰 한도 — **맥 기본값과 같은 1.5초 · 깊이 64**(`GomokuAISearchLimits()`), 명시만 한다.
    ///
    /// 엔진은 시간으로 끊긴다(256 노드마다 마감·취소를 본다 — `GomokuAIEngine.tick`, 반복 한 바퀴가 끝났을 때 예산의 45% 를 넘겼으면
    /// 더 깊이 가지 않는다). 그래서 폰 CPU 가 느리면 **기다림이 길어지는 게 아니라 깊이가 얕아진다** — 사람이 보는 "생각 중"은
    /// 폰에서도 최대 약 1.5초(+ 코어의 최소 표시 0.6초와 겹친다)다. 실측(맥 디버그 빌드, 자기대국 24수): 한 수 최대 1.553초 · 평균 0.71초,
    /// 첫 호출의 줄 모양 표 준비 0.62초(디버그 — 최적화 빌드는 훨씬 짧다). 예산을 줄이면 단일 난이도("항상 최선")가 폰에서만
    /// 약해진다 — 맥과 같은 값을 쓰고, 달라져야 하면 이 한 줄을 바꾼다(코어 기본값은 맥의 것이라 건드리지 않는다).
    package static let phoneLimits = GomokuAISearchLimits(timeBudget: .milliseconds(1500), maxDepth: 64)

    /// 진짜 엔진.
    package static let realEngine: Engine = { board, color, limits, isCancelled in
        GomokuAI.bestMove(board: board, toMove: color, limits: limits, isCancelled: isCancelled)
    }

    package var engine: Engine = GamesGomokuAIThinker.realEngine
    package var limits: GomokuAISearchLimits = GamesGomokuAIThinker.phoneLimits
    /// 이 판·색의 수가 아직 필요한가(코어 AI 판이 그 판에서 AI 차례로 멈춰 있는가). `GamesStore` 가 코어 상태로 채운다.
    /// 필요 없으면 **다시 생각하지 않는다** — 기권한 판을 화면에 돌아올 때 1.5초 더 생각하던 낭비를 막는다. 코어는 그때 결과를 어차피 버린다.
    package var isStillNeeded: @MainActor (GomokuBoard, GomokuColor) -> Bool = { _, _ in true }

    /// 생각해도 되는가(오목 화면이 보이고 앱이 active). `GamesStore` 가 수명 사건마다 적는다.
    package private(set) var isAllowed = false
    /// 도는 엔진(한 번에 하나 — 코어가 AI 차례마다 선택기를 한 번 부른다).
    private var running: Task<GomokuPoint?, Never>?
    /// 허락을 기다리는 선택기 호출.
    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    /// 엔진을 띄운 횟수(진단·테스트 지점).
    package private(set) var searchesStarted = 0
    /// 화면을 떠나거나 background 로 가서 끊은 탐색 수(진단·테스트 지점).
    package private(set) var searchesInterrupted = 0

    package var isSearching: Bool { running != nil }
    /// 허락을 기다리며 붙잡힌 선택기 호출 수.
    package var waitingCount: Int { waiters.count }

    package init() {}

    /// 코어 스토어에 끼울 선택기. 약참조 — 선택기가 이 객체를 붙잡아 두지 않는다.
    package var chooser: GomokuAIMoveChooser {
        { [weak self] board, color in
            guard let self else { return nil }
            return await self.choose(board: board, color: color)
        }
    }

    /// 허락을 바꾼다. 거두면 도는 엔진을 취소하고, 주면 기다리던 호출을 깨운다.
    package func setAllowed(_ allowed: Bool) {
        guard allowed != isAllowed else { return }
        isAllowed = allowed
        if allowed {
            let pending = waiters
            waiters = [:]
            for continuation in pending.values { continuation.resume() }
        } else {
            running?.cancel()
        }
    }

    /// 선택기 한 번. 허락이 있을 때만 엔진을 띄우고, 떠나서 끊긴 탐색은 버린 뒤 돌아오면 다시 생각한다.
    /// 부른 쪽(코어의 AI 수 작업)이 취소되면 nil — 코어는 그 결과를 버린다.
    package func choose(board: GomokuBoard, color: GomokuColor) async -> GomokuPoint? {
        while !Task.isCancelled {
            guard isStillNeeded(board, color) else { return nil }
            guard isAllowed else {
                await waitUntilAllowed()
                continue
            }
            let engine = self.engine
            let limits = self.limits
            // 메인 액터 밖(분리된 작업)에서 돈다 — 코어 기본 선택기와 같은 수법. 엔진이 보는 취소는 이 작업의 취소다.
            let search = Task.detached(priority: .userInitiated) {
                engine(board, color, limits, { Task.isCancelled })
            }
            running = search
            searchesStarted += 1
            let move = await withTaskCancellationHandler {
                await search.value
            } onCancel: {
                search.cancel()
            }
            if running == search { running = nil }
            guard search.isCancelled else { return move }
            // 끊긴 탐색의 수는 덜 생각한 수다 — 버린다. 부른 쪽이 취소됐으면 고리 조건이 끝내고, 떠나서 끊겼으면 돌아올 때까지 기다린다.
            if !Task.isCancelled { searchesInterrupted += 1 }
        }
        return nil
    }

    private func waitUntilAllowed() async {
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                if isAllowed || Task.isCancelled {
                    continuation.resume()
                } else {
                    waiters[id] = continuation
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.resumeWaiter(id) }
        }
    }

    private func resumeWaiter(_ id: UUID) {
        waiters.removeValue(forKey: id)?.resume()
    }
}

// MARK: - 대국·결과 화면의 판 종류별 표

/// 대국·결과 화면이 **판 종류**(사람 · AI)에 따라 세우는 것. 뷰는 이 표만 읽는다 — 사람 판 값은 w15 그대로이고 테스트가 글자로 못 박는다
/// (`GamesAIMatchTests` "사람 판 화면 표는 그대로다").
///
/// AI 판에서 서지 않는 것: 판돈 줄(내비 부제 · 결과 루비 변화 — 걸린 루비가 없다) · 대화 서랍(상대가 사람이 아니다 → 서랍 머리의
/// 신고·차단 메뉴도 함께 없다) · 상대 캐릭터 초상·근무 상태(사람 프로필이 없다). 맥 AI 판(`GomokuMatchSide.isAI` 갈래)과 같은 목록이다.
package struct GomokuPhoneMatchChrome: Equatable, Sendable {
    package let isAI: Bool

    package init(isAI: Bool) {
        self.isAI = isAI
    }

    /// 판 id 머리말로 가른다(코어 서버 차단과 **같은 판정** — `GomokuAIGame.isAIMatchID`).
    package init(match: GomokuMatchState) {
        self.init(isAI: GomokuAIGame.isAIMatchID(match.id))
    }

    /// 판돈 줄(내비 부제)과 결과 루비 변화.
    package var showsStake: Bool { !isAI }
    /// 대화 서랍(신고·차단 메뉴가 그 머리에 있다).
    package var showsChatDrawer: Bool { !isAI }

    package var resignConfirmTitle: String { isAI ? GomokuPhoneText.aiResignConfirm : GomokuPhoneText.resignConfirm }
    package var resignConfirmMessage: String { isAI ? GomokuPhoneText.aiNoRecord : GomokuPhoneText.resignConfirmMessage }
    /// 판 아래 시계 안내 한 줄. 사람 판은 서버 시계(앱을 나가도 흐른다), AI 판은 로컬 시계(떠나면 멈춘다).
    package var clockLine: String { isAI ? GomokuPhoneText.aiClockPauses : GomokuPhoneText.clockRunsInBackground }
    package var rematchTitle: String { isAI ? GomokuPhoneText.aiRematch : GomokuPhoneText.rematch }

    /// 내 카드 부제(상대 차례). AI 차례면 맥 상태줄과 같은 "AI가 생각 중이에요".
    package func waitingLine(myColor: GomokuColor) -> String {
        isAI ? GomokuPhoneText.stoneShort(myColor) + " · " + GomokuPhoneText.aiThinking : GomokuPhoneText.myWaitingLine(color: myColor)
    }

    /// 상대 카드 부제. AI 는 근무 상태가 없다 — 맥 AI 카드처럼 돌 이름만.
    package func opponentSubtitle(color: GomokuColor, isWorking: Bool) -> String {
        isAI ? GomokuPhoneText.stoneName(color) : GomokuPhoneText.playerSubtitle(color: color, isWorking: isWorking)
    }

    package func endReason(_ reason: GomokuEndReason?, outcome: GomokuOutcome?) -> String {
        isAI ? GomokuPhoneText.aiEndReason(reason, outcome: outcome) : GomokuPhoneText.endReason(reason, outcome: outcome)
    }

    package func opponentLine(name: String) -> String {
        isAI ? GomokuPhoneText.aiOpponentLine : GomokuPhoneText.resultOpponent(name)
    }
}
