import Foundation
import OSLog
import CheckCore

// MARK: - 미니게임 허브 (v0.2.46) — 패널 상태 · 최고기록 · 오늘 순위 · 공개 설정
//
// 게임 규칙은 여기 없다(MiniGameTimingBar / MiniGameFlappy 의 값 타입). 스토어는 패널 열고 닫기, 판이 끝난 점수의
// 로컬 최고 갱신과 업로드, 오늘(KST) 순위와 어제 1등 조회, 공개 토글만 맡는다. 순위 조회는 **열림·재오픈·제출 성공·
// 종류 전환 때만** 한다 — 30초 refresh 루프에 얹지 않는다(38명 × 30초에 곱해지는 요청은 무료 플랜의 몫이 아니다).

extension WorkTimerStore {
    /// 미니게임 경로의 진단 로그. 실패가 화면엔 "점수를 못 올렸어요" 한 줄로만 남아서, 그게 토큰
    /// 요청 실패인지·제출 시점 토큰 없음인지·서버 거절인지 갈리지 않았다(2026-09-14 신고 때 `log show`
    /// 로 확인하려 했는데 이 경로에 로그가 한 줄도 없었다).
    /// ⚠️ 거절 **status 이름까지만** 남긴다 — `need_seconds`/`elapsed_seconds` 는 "얼마나 더 기다리면
    ///    통과하는지"라서 로그(사용자가 볼 수 있다)에 남기면 위조 보조 도구가 된다.
    static var miniGameLogger: Logger { Logger(subsystem: "kingcheck", category: "minigame") }

    /// 토큰을 새로 받는 기준(초). 서버 TTL 30분보다 넉넉히 짧게 잡아, 만료된 토큰으로 제출해
    /// 판을 통째로 버리는 일이 없게 한다.
    ///
    /// ⚠️ v0.3.38 부터 **게임별**이다 — 판정은 `MiniGameKind.roundTokenReuseSeconds` 한 곳에서 나온다(테트리스는 12분).
    /// 이 상수는 기존 두 게임의 값(20분)을 가리키는 별명으로 남긴다: 여기를 고쳐도 테트리스는 안 움직인다.
    static let miniGameTokenRefreshSeconds: TimeInterval = MiniGameKind.flappy.roundTokenReuseSeconds

    /// 로컬 최고기록 키. **계정별**이다 — 같은 맥을 다른 계정이 쓰면 남의 최고를 물려받지 않게(로그아웃 리셋 대상이 아닌 이유).
    static func miniGameBestKey(userID: String?, kind: MiniGameKind) -> String {
        "check.minigame.best.\(userID ?? "local").\(kind.rawValue)"
    }

    // MARK: 창 열고 닫기

    /// 팝오버 오른쪽 레일의 미니게임 버튼(v0.2.48 에 캡션 행에서 이사)의 액션. **별도 창**을 열고(v0.2.46) 오늘 순위를 받는다.
    ///
    /// 다른 패널을 닫지 않는다 — 창은 팝오버와 공존한다(다른 패널을 열어도 게임은 계속된다).
    /// 이미 열려 있어도 `show()` 는 멱등이라 앞으로 가져오기만 한다(최소화해 뒀다면 되살린다).
    ///
    /// **팝오버는 닫는다**(v0.2.49). 사용자 요구 2026-09-10: "미니게임 버튼은 눌렀을 때 미니게임 창
    /// 열리면서 상단 탭바 화면은 닫히게 해줘." 지금까지는 게임 창을 열어도 팝오버가 그 위에 남아
    /// 화면을 가렸다 — 창을 띄우는 `NSApp.activate()` 경로로는 팝오버가 닫히지 않는다는 것을
    /// 실측으로 확인했다(근거 표는 `WindowTopAnchor.dismissMenuPopover` 주석).
    ///
    /// 순서가 **창 먼저, 팝오버 나중**인 이유가 둘이다.
    ///  · 이 메서드는 팝오버 **안의** 버튼이 부른다. 먼저 닫으면 자기를 그린 뷰 계층을 액션 도중에 걷어낸다.
    ///  · 닫는 수단이 상태바 아이템 클릭이라, 창이 먼저 키를 가져간 뒤 눌러야 포커스가 게임 창에 남는다.
    ///
    /// **판은 안 끊긴다.** `miniGameInterruptToken` 을 올리는 곳은 게임 창 자신의 닫힘·포커스 상실뿐이고
    /// (`CheckMiniGameWindowController`), 팝오버가 닫히며 흐르는 `setMenuPresented(false)` 는 그 토큰을
    /// 건드리지 않는다 — 그 사실은 소스 계약 테스트가 이미 못 박고 있다.
    func openMiniGameWindow() {
        if !isMiniGamePanelVisible { isMiniGamePanelVisible = true }
        // 첫 프레임부터 빈 목록 자리에 "불러오는 중…"이 뜨게 한다(토큰 보드와 같은 규약 — 본문 자리에 동기화 문구 금지).
        if !miniGameBoardLoaded { miniGameBoardLoading = true }
        loadMiniGameBoard()
        // 토큰을 **여기서** 미리 받는다. 판 시작에 받으면 플래피 즉사처럼 1초 안에 끝나는 판은
        // 왕복이 못 끝나 점수를 통째로 버린다(신고 2026-09-14의 둘째 원인). 일찍 받을수록
        // 서버가 재는 경과가 길어져 **더 관대해진다** — 정직한 플레이를 막을 수 없는 방향이다.
        prefetchMiniGameRoundToken(kind: miniGameKind)
        CheckMiniGameWindowController.shared.show()
        WindowTopAnchor.dismissMenuPopover()
    }

    /// 진입 버튼을 다시 눌렀을 때(열려 있으면 닫고, 아니면 연다). 창을 쓰는 지금도 남겨 두는 이유는 같은 버튼이
    /// 토글로 읽히기 때문이다 — 열린 창을 한 번 더 눌러 닫을 수 있어야 한다.
    func toggleMiniGamePanel() {
        if isMiniGamePanelVisible {
            closeMiniGamePanel()
            return
        }
        openMiniGameWindow()
    }

    /// 미니게임 창을 닫는다(진행 중인 판도 끝낸다 — interruptToken). 사용자가 타이틀바 빨간 점을 눌렀을 때는
    /// 컨트롤러의 `windowWillClose` 가 같은 두 값을 직접 맞춘다(그쪽은 `close()` 를 거치지 않는 경로다).
    /// 이미 닫혀 있으면 아무것도 하지 않는다 — 헛되이 토큰을 올려 잎 뷰를 깨우지 않게.
    func closeMiniGamePanel() {
        guard isMiniGamePanelVisible else { return }
        isMiniGamePanelVisible = false
        miniGameInterruptToken += 1
        CheckMiniGameWindowController.shared.close()
    }

    /// 진행 중인 판을 **사용자 의사로** 접는다(정지 카드의 [그만두기] — v0.2.48).
    ///
    /// 하는 일은 `miniGameInterruptToken += 1` 하나뿐이다. 그런데도 새 메서드를 낸 이유: 지금까지 이 토큰을
    /// 올리는 길은 창 컨트롤러가 스토어 프로퍼티를 **직접** 만지는 경로(`windowWillClose` · `windowDidResignKey`)
    /// 뿐이었고, 화면에서 부를 이름이 없었다. 창 닫힘·포커스 상실과 같은 신호를 **사용자 의사**로 보내는 문이다.
    ///
    /// 판을 어떻게 접을지는 게임이 정한다 — 플래피는 그 순간 점수로 결과 확정, 타이밍 바는 10라운드를 못
    /// 채웠으므로 무효(`MiniGameHost.interruptToken` 주석). 스토어는 그 차이를 모른다.
    /// 창은 그대로 둔다(`isMiniGamePanelVisible` 을 안 내린다) — 그만둔 사람은 대개 다른 게임을 하려는 것이다.
    func abortMiniGameRound() {
        miniGameInterruptToken += 1
    }

    /// 게임 종류 전환. 진행 중인 판을 끝내고(토큰) 그 게임의 오늘 순위를 다시 받는다. 선택은 영속한다.
    func selectMiniGame(_ kind: MiniGameKind) {
        guard kind != miniGameKind else { return }
        miniGameKind = kind
        defaults.set(kind.rawValue, forKey: Self.miniGameKindKey)
        miniGameInterruptToken += 1
        // 지난 게임의 토큰은 여기서 버린다. 서버가 게임까지 대조하므로 남겨 둬도 사고는 안 나지만,
        // 남은 값이 "쓸 수 있는 토큰"처럼 보이면 다음 사람이 그렇게 읽는다.
        miniGameRoundToken = nil
        miniGameRoundTokenKind = nil
        miniGameRoundTokenAt = nil
        miniGameRoundGeneration += 1
        miniGameSubmitNotice = nil
        // 바뀐 게임의 토큰을 미리 받아 둔다 — 첫 판이 짧아도(플래피 즉사) 왕복이 끝나 있다.
        prefetchMiniGameRoundToken(kind: kind)
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

    /// 판이 **시작됐다**(게임 잎 뷰의 onPlayingChanged(true)). 서버에서 이 판의 토큰을 받아 둔다.
    ///
    /// ★ **반드시 시작 시점이어야 한다.** 서버는 토큰 발급 시각부터 제출까지의 경과가 그 점수를 낼 수
    ///   있는 **구조적 최소 시간**보다 긴지 본다(타이밍바는 10라운드 주기 합의 절반, 플래피는
    ///   기둥간격/속도의 누적 합 — 게임 상수에서 나오는 물리량이라 정직한 플레이는 정의상 못 깬다).
    ///   끝날 때 받으면 경과가 0 이라 무조건 거절된다.
    ///
    /// ★ **게임을 막지 않는다.** Task 로 띄우고 응답을 기다리지 않는다 — 네트워크 때문에 60Hz 판이
    ///   버벅이면 안 된다. 토큰이 늦거나 못 오면 그 판은 못 올리고, 그 사실을 사용자에게 말한다.
    /// 들고 있는 토큰이 이 게임에 **지금 쓸 수 있는가.** TTL(서버 30분)에 닿기 전에 새로 받으려고
    /// 여유를 크게 둔다 — 만료된 토큰으로 제출하면 그 판은 통째로 못 올린다.
    func hasUsableMiniGameToken(for kind: MiniGameKind) -> Bool {
        guard miniGameRoundToken != nil, miniGameRoundTokenKind == kind,
              let issued = miniGameRoundTokenAt else { return false }
        // 나이 기준은 **게임별**이다(테트리스 판은 길어서 12분 — MiniGameKind.roundTokenReuseSeconds 의 검산).
        return Date().timeIntervalSince(issued) < kind.roundTokenReuseSeconds
    }

    /// 토큰을 **미리** 받아 둔다. 게임 창을 열 때·게임을 바꿀 때·제출이 끝난 뒤에 부른다.
    ///
    /// ★ **일찍 받을수록 안전하다.** 서버의 시간 하한은 `started_at` 기준이라 토큰이 오래될수록
    ///   경과가 길어져 **더 관대해진다**(정직한 플레이를 막을 수 없다). 반대로 늦게 받으면 막힌다 —
    ///   플래피 즉사처럼 1초 안에 끝나는 판은 판 시작에 요청해서는 왕복이 못 끝난다.
    /// 이미 쓸 수 있는 토큰을 들고 있으면 **다시 받지 않는다** — 다시 받으면 서버가 `started_at` 을
    ///   now() 로 되돌려(행을 갈아 끼운다) 애써 벌어 둔 여유가 사라진다.
    func prefetchMiniGameRoundToken(kind: MiniGameKind) {
        guard miniGamePublic, session != nil else { return }
        guard !hasUsableMiniGameToken(for: kind) else { return }
        requestMiniGameRoundToken(kind: kind)
    }

    /// 판이 **시작됐다**(게임 잎 뷰의 onPlayingChanged(true)).
    ///
    /// 선발급이 성공해 쓸 수 있는 토큰을 이미 들고 있으면 **아무것도 하지 않는다**(위 주석의 그 이유).
    /// 선발급이 실패했거나 토큰이 오래됐을 때만 여기서 받는다 — 그 경우에도 게임을 막지 않는다.
    func beginMiniGameRound(kind: MiniGameKind) {
        guard miniGamePublic, session != nil else { return }
        miniGameSubmitNotice = nil
        guard !hasUsableMiniGameToken(for: kind) else { return }
        requestMiniGameRoundToken(kind: kind)
    }

    /// 토큰 요청 한 번. **세대를 올리고** 그 세대로 응답을 검증한다.
    func requestMiniGameRoundToken(kind: MiniGameKind) {
        // 지금 들고 있는 것은 버린다 — 서버가 행을 갈아 끼우므로 새 요청이 나가는 순간 죽는다.
        miniGameRoundToken = nil
        miniGameRoundTokenKind = nil
        miniGameRoundTokenAt = nil
        miniGameRoundGeneration += 1
        let generation = miniGameRoundGeneration
        Task { @MainActor in await performBeginMiniGameRound(kind: kind, roundGeneration: generation) }
    }

    /// 위의 본체. 실패는 **조용히** — 토큰이 없는 것은 제출 시점에 한 줄로 알린다(두 번 말하지 않는다).
    func performBeginMiniGameRound(kind: MiniGameKind, roundGeneration: Int) async {
        guard session != nil else { return }
        let generation = sessionGeneration
        do {
            let response = try await withSessionRetry { activeSession in
                try await service.startMiniGameRound(accessToken: activeSession.accessToken, kind: kind)
            }
            guard generation == sessionGeneration else { return }
            // ★ **늦게 온 응답은 버린다.** 서버는 (user_id, game) 당 미사용 토큰을 한 행만 두고
            //   start_round 가 그 행의 id 를 갈아 끼우므로, 내 뒤에 나간 요청이 있었다면 내 토큰은
            //   이미 죽었다. 세대가 밀렸으면 그걸로 덮지 않는다(실사용 신고 2026-09-14의 원인).
            guard roundGeneration == miniGameRoundGeneration else { return }
            guard let token = response.token, response.status == "ok" else {
                Self.miniGameLogger.notice(
                    "round token refused status=\(response.status, privacy: .public) game=\(kind.rawValue, privacy: .public)")
                return
            }
            miniGameRoundToken = token
            miniGameRoundTokenKind = kind
            miniGameRoundTokenAt = Date()
        } catch {
            // 취소·오프라인·스키마 부재(서버 배포 전 창) 전부 여기로 온다. 토큰이 없는 채로 두고,
            // 판이 끝나면 recordMiniGameScore 가 한 줄로 알린다.
            guard roundGeneration == miniGameRoundGeneration else { return }
            Self.miniGameLogger.notice("round token request failed game=\(kind.rawValue, privacy: .public)")
        }
    }

    /// 유효하게 끝난 판의 점수(게임 잎 뷰의 onFinished). 범위 밖(음수·상한 초과)은 버린다 — 서버 check 제약과 같은 값이라
    /// 보내 봐야 400 이다. 로컬 최고를 올리고, 공개가 켜져 있으면 **판마다** 올린다(최고 유지·판 수는 서버 몫).
    func recordMiniGameScore(kind: MiniGameKind, score: Int) {
        guard score >= 0, score <= kind.maxScore else { return }
        raiseMiniGameBest(kind, to: score)
        // 공개를 끈 사람은 순위표에 없고, 그래서 올릴 이유도 없다(끄면 "올라가지도 않아요" — 설정 문구가 약속한 것).
        guard miniGamePublic, session != nil else { return }
        // 토큰이 없으면 **보내지 않는다**(서버가 어차피 no_token 으로 거절한다). 조용히 버리지 않고 말한다.
        guard let token = miniGameRoundToken, miniGameRoundTokenKind == kind else {
            Self.miniGameLogger.notice(
                "submit skipped — no token game=\(kind.rawValue, privacy: .public) score=\(score, privacy: .public)")
            miniGameSubmitNotice = "점수를 못 올렸어요 — 연결을 확인하고 다시 해 주세요"
            // 다음 판은 되게 해 둔다(선발급).
            prefetchMiniGameRoundToken(kind: kind)
            return
        }
        // 한 토큰에 한 점수다. 여기서 비워 두면 같은 토큰이 두 번 나가지 않는다.
        miniGameRoundToken = nil
        miniGameRoundTokenKind = nil
        miniGameRoundTokenAt = nil
        Task { @MainActor in await performSubmitMiniGameScore(kind: kind, score: score, token: token) }
    }

    /// 점수 업로드(performLoadTokenBoard 관용구: 세션 가드 → 세대 캡처 → withSessionRetry → 세대 가드). 성공하면 패널이
    /// 보이는 동안 오늘 순위를 다시 받아 방금 판이 바로 반영되게 한다.
    ///
    /// **거절은 화면에 말한다.** 예전에는 실패를 통째로 삼켰는데, 그때는 실패가 "서버가 아직 없다" 정도였다.
    /// 지금은 토큰 방식이라 거절이 곧 "이 판은 순위표에 안 올라간다"이고, 그걸 안 알리면
    /// "잘 놀았는데 순위표에 없다"가 된다 — 재현도 신고도 안 되는 종류다.
    func performSubmitMiniGameScore(kind: MiniGameKind, score: Int, token: String) async {
        guard session != nil else { return }
        let generation = sessionGeneration
        do {
            let response = try await withSessionRetry { activeSession in
                try await service.submitMiniGameScore(
                    accessToken: activeSession.accessToken, kind: kind, score: score, token: token)
            }
            guard generation == sessionGeneration else { return }
            if response.status == "ok" {
                // 서버가 확정한 최고를 로컬에도 올린다(다른 맥에서 세운 기록이 섞여 있을 수 있다).
                if let best = response.bestScore { raiseMiniGameBest(kind, to: best) }
                miniGameSubmitNotice = nil
                // 창이 열려 있으면 재조회한다(팝오버는 닫혀 있어도 된다 — 게임은 별도 창이다).
                if isMiniGamePanelVisible, miniGameKind == kind {
                    await performLoadMiniGameBoard()
                }
            } else {
                // ⚠️ `need_seconds`/`elapsed_seconds` 는 **화면에도 로그에도 쓰지 않는다** — "얼마나 더
                //    기다리면 통과하는지"를 알려 주는 순간 그건 위조 보조 도구다. status 이름이면 진단에 충분하다.
                Self.miniGameLogger.notice(
                    "submit refused status=\(response.status, privacy: .public) game=\(kind.rawValue, privacy: .public)")
                // 토큰 만료만 이유를 밝힌다. 사람이 고칠 수 있는 유일한 거절이고("판을 너무 오래 끌었다"),
                // 위조 보조가 되지 않는다 — 위조에 쓸모 있는 것은 `too_fast` 의 `need_seconds` 쪽이고 그건
                // 화면에도 로그에도 안 쓴다(바로 위 주석). 나머지는 이유를 밝히지 않는다.
                miniGameSubmitNotice = response.status == "token_expired"
                    ? "판이 너무 오래 걸려 기록하지 못했어요"
                    : "점수를 못 올렸어요"
            }
            // 성공이든 거절이든 다음 판을 위해 새 토큰을 미리 받아 둔다(방금 쓴 토큰은 죽었다).
            prefetchMiniGameRoundToken(kind: kind)
        } catch {
            if case .cancelled = classifyAuthError(error) { return }
            guard generation == sessionGeneration else { return }
            Self.miniGameLogger.notice("submit failed (network) game=\(kind.rawValue, privacy: .public)")
            miniGameSubmitNotice = "점수를 못 올렸어요 — 연결을 확인하고 다시 해 주세요"
            prefetchMiniGameRoundToken(kind: kind)
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
