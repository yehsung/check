import Foundation

// MARK: - 미니게임 허브 (v0.2.46) — 패널 상태 · 최고기록 · 오늘 순위 · 공개 설정
//
// 게임 규칙은 여기 없다(MiniGameTimingBar / MiniGameFlappy 의 값 타입). 스토어는 패널 열고 닫기, 판이 끝난 점수의
// 로컬 최고 갱신과 업로드, 오늘(KST) 순위와 어제 1등 조회, 공개 토글만 맡는다. 순위 조회는 **열림·재오픈·제출 성공·
// 종류 전환 때만** 한다 — 30초 refresh 루프에 얹지 않는다(38명 × 30초에 곱해지는 요청은 무료 플랜의 몫이 아니다).

extension WorkTimerStore {
    /// 로컬 최고기록 키. **계정별**이다 — 같은 맥을 다른 계정이 쓰면 남의 최고를 물려받지 않게(로그아웃 리셋 대상이 아닌 이유).
    static func miniGameBestKey(userID: String?, kind: MiniGameKind) -> String {
        "check.minigame.best.\(userID ?? "local").\(kind.rawValue)"
    }

    // MARK: 패널 열고 닫기

    /// 미니게임 버튼 액션. 패널을 토글하고, 여는 순간 오늘 순위를 로드한다. 다른 다섯 패널과 상호 배타.
    func toggleMiniGamePanel() {
        if isMiniGamePanelVisible {
            closeMiniGamePanel()
            return
        }
        isMiniGamePanelVisible = true
        isLeaderboardVisible = false
        closeTokenBoard()
        closePokePanel()
        closeUltraPanel()
        isInsightsPanelVisible = false
        // 첫 프레임부터 빈 목록 자리에 "불러오는 중…"이 뜨게 한다(토큰 보드와 같은 규약 — 본문 자리에 동기화 문구 금지).
        if !miniGameBoardLoaded { miniGameBoardLoading = true }
        loadMiniGameBoard()
    }

    /// 미니게임 패널을 닫는 **유일한** 경로. 뒤로 버튼·토글·다른 패널 열기가 모두 여기를 지나야 진행 중인 판이 끝난다
    /// (interruptToken). 이미 닫혀 있으면 아무것도 하지 않는다 — 다른 토글이 부를 때 헛되이 토큰을 올려 잎 뷰를 깨우지 않게.
    func closeMiniGamePanel() {
        guard isMiniGamePanelVisible else { return }
        isMiniGamePanelVisible = false
        miniGameInterruptToken += 1
    }

    /// 게임 종류 전환. 진행 중인 판을 끝내고(토큰) 그 게임의 오늘 순위를 다시 받는다. 선택은 영속한다.
    func selectMiniGame(_ kind: MiniGameKind) {
        guard kind != miniGameKind else { return }
        miniGameKind = kind
        defaults.set(kind.rawValue, forKey: Self.miniGameKindKey)
        miniGameInterruptToken += 1
        // 이전 게임의 행이 잠깐 남아 '이 게임 순위인 척' 보이지 않도록 비우고 로드 전 상태로 되돌린다.
        miniGameBoard = []
        miniGameBoardLoaded = false
        miniGameBoardFailed = false
        miniGameYesterdayWinner = nil
        miniGameBoardLoading = true
        loadMiniGameBoard()
    }

    // MARK: 최고기록 · 제출

    /// 이 계정·이 게임의 로컬 최고기록(전체 기간). 결과 화면의 "최고 N"과 신기록 판정에 쓴다.
    func miniGameBest(_ kind: MiniGameKind) -> Int {
        max(0, defaults.integer(forKey: Self.miniGameBestKey(userID: session?.userID, kind: kind)))
    }

    /// 로컬 최고를 올린다(내려가지 않는다). 순위 응답의 내 행이 로컬보다 클 때(다른 맥에서 세운 기록)도 여기로 온다.
    func raiseMiniGameBest(_ kind: MiniGameKind, to score: Int) {
        guard score > miniGameBest(kind) else { return }
        defaults.set(score, forKey: Self.miniGameBestKey(userID: session?.userID, kind: kind))
    }

    /// 유효하게 끝난 판의 점수(게임 잎 뷰의 onFinished). 범위 밖(음수·상한 초과)은 버린다 — 서버 check 제약과 같은 값이라
    /// 보내 봐야 400 이다. 로컬 최고를 올리고, 공개가 켜져 있으면 **판마다** 올린다(최고 유지·판 수는 서버 트리거 몫).
    func recordMiniGameScore(kind: MiniGameKind, score: Int) {
        guard score >= 0, score <= kind.maxScore else { return }
        raiseMiniGameBest(kind, to: score)
        // 공개를 끈 사람은 순위표에 없고, 그래서 올릴 이유도 없다(끄면 "올라가지도 않아요" — 설정 문구가 약속한 것).
        guard miniGamePublic, session != nil else { return }
        Task { @MainActor in await performSubmitMiniGameScore(kind: kind, score: score) }
    }

    /// 점수 업로드(performLoadTokenBoard 관용구: 세션 가드 → 세대 캡처 → withSessionRetry → 세대 가드). 성공하면 패널이
    /// 보이는 동안 오늘 순위를 다시 받아 방금 판이 바로 반영되게 한다. 실패는 조용히 — 스키마 부재(마이그레이션 전 창)도
    /// 실패 표시 없이 삼킨다(순위 조회의 실패 플래그는 조회의 것이지 제출의 것이 아니다).
    func performSubmitMiniGameScore(kind: MiniGameKind, score: Int) async {
        guard session != nil else { return }
        let generation = sessionGeneration
        do {
            try await withSessionRetry { activeSession in
                try await service.upsertMiniGameScore(
                    accessToken: activeSession.accessToken, userID: activeSession.userID, kind: kind, score: score)
            }
            guard generation == sessionGeneration else { return }
            if isMenuPresented, isMiniGamePanelVisible, miniGameKind == kind {
                await performLoadMiniGameBoard()
            }
        } catch {
            if case .cancelled = classifyAuthError(error) { return }
            // 그 외(스키마 부재·5xx·오프라인)는 조용히 — 로컬 최고는 이미 올랐고, 다음 판이 다시 올린다.
        }
    }

    // MARK: 오늘 순위 · 어제 1등

    /// 오늘 순위를 로드한다(Task 발사). 패널을 여는 순간·팝오버 재오픈·종류 전환·제출 성공에서 호출한다.
    func loadMiniGameBoard() {
        Task { @MainActor in await performLoadMiniGameBoard() }
    }

    /// minigame_board(오늘) + minigame_yesterday_winner 를 받아 반영한다. 두 조회는 **독립 실패**다 — 어제 1등을 못 받아도
    /// 오늘 순위는 그린다. 응답이 오는 사이 게임 종류를 바꿨으면 낡은 게임의 응답이라 버린다(월 이동 스냅백과 같은 규약).
    func performLoadMiniGameBoard() async {
        guard session != nil else { return }
        let kind = miniGameKind
        let generation = sessionGeneration
        if !miniGameBoardLoading { miniGameBoardLoading = true }
        if miniGameBoardFailed { miniGameBoardFailed = false }
        defer { if kind == miniGameKind, miniGameBoardLoading { miniGameBoardLoading = false } }
        do {
            let entries = try await withSessionRetry { activeSession in
                try await service.fetchMiniGameBoard(accessToken: activeSession.accessToken, kind: kind, day: nil)
            }
            guard generation == sessionGeneration, kind == miniGameKind else { return }
            let sorted = entries.sortedForMiniGameBoard()
            if miniGameBoard != sorted { miniGameBoard = sorted }
            if !miniGameBoardLoaded { miniGameBoardLoaded = true }
            if miniGameBoardFailed { miniGameBoardFailed = false }
            // 내 행이 로컬 최고보다 크면(다른 맥에서 세운 기록) 로컬 캐시를 올린다 — "최고 N"이 맥마다 다르게 보이지 않게.
            if let me = session?.userID, let mine = sorted.first(where: { $0.userID == me }) {
                raiseMiniGameBest(kind, to: mine.bestScore)
            }
        } catch {
            if case .cancelled = classifyAuthError(error) { return }
            guard generation == sessionGeneration, kind == miniGameKind else { return }
            if case SupabaseWorkServiceError.databaseSchemaMissing = error {
                // 마이그레이션 전 창(브루 배포가 db push 보다 앞선 경우): 실패가 아니라 '아직 표가 없다'. 빈 목록으로 조용히 접는다 —
                // 실패 문구와 [다시 시도] 는 사용자가 고칠 수 있는 일에만 쓴다.
                if !miniGameBoardLoaded { miniGameBoardLoaded = true }
            } else {
                if !miniGameBoardFailed { miniGameBoardFailed = true }
            }
            return
        }
        // 어제 1등(상품 표시). 실패해도 위 순위는 이미 반영됐다.
        let winner = try? await withSessionRetry { activeSession in
            try await service.fetchMiniGameYesterdayWinner(accessToken: activeSession.accessToken, kind: kind)
        }
        guard generation == sessionGeneration, kind == miniGameKind else { return }
        if let winner, miniGameYesterdayWinner != winner { miniGameYesterdayWinner = winner }
        if winner == nil, miniGameYesterdayWinner != nil { miniGameYesterdayWinner = nil }
    }

    // MARK: 공개 설정

    /// 미니게임 순위 공개 토글(낙관 반영 → PATCH, 실패 시 원복). 토큰 공개 토글과 같은 규약이다.
    func setMiniGamePublic(_ isPublic: Bool) {
        guard miniGamePublic != isPublic else { return }
        let previous = miniGamePublic
        miniGamePublic = isPublic
        // 사용자가 명시적으로 정한 값이므로 로드 완료로 간주한다(폴링 첫 tick 이 이 선택을 덮지 않게).
        miniGamePublicLoaded = true
        guard session != nil else { return }
        let generation = sessionGeneration
        Task { @MainActor in
            do {
                try await withSessionRetry { activeSession in
                    try await service.updateMiniGamePublic(
                        accessToken: activeSession.accessToken, userID: activeSession.userID, isPublic: isPublic)
                }
            } catch {
                if case .cancelled = classifyAuthError(error) { return }
                guard generation == sessionGeneration else { return }
                miniGamePublic = previous
            }
        }
    }
}
