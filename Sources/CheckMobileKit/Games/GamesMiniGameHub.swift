import CheckCore
import Foundation
import Observation
import OSLog

/// 한 게임의 오늘 순위 칸.
package struct GamesMiniGameBoard: Equatable {
    package var entries: [MiniGameBoardEntry] = []
    package var yesterdayWinner: MiniGameWinner?
    /// 이번 로그인에서 한 번이라도 받았다(빈 목록을 "아직 모른다"와 가른다).
    package var loaded = false
    package var loading = false
    package var failed = false

    package init() {}

    /// 오늘 한 사람 수를 **안다**(정족수 줄 "오늘은 아직 아무도 안 했어요 · 5명부터 지급"을 그려도 된다).
    /// 줄이 하나라도 있으면 적어도 그만큼은 했다. 비어 있으면 받은 적이 있고 마지막 조회가 실패하지 않았을 때만 0명이다 —
    /// 불러오지 못한 순위를 "아무도 안 했다"로 말하지 않는다(games-verify: 실패 카드에 두 말이 함께 떴다).
    package var knowsPlayerCount: Bool {
        MobileLoadKnowledge.knowsCount(hasRows: !entries.isEmpty, hasLoaded: loaded, lastFailed: failed)
    }

    /// 빈 순위 자리를 무엇으로 채우는가(공용 규칙 — 순위 탭 미니게임 판과 같다).
    package var placeholder: MobileLoadKnowledge.Placeholder {
        MobileLoadKnowledge.placeholder(hasRows: !entries.isEmpty, hasLoaded: loaded, lastFailed: failed)
    }
}

/// 미니게임 허브(SPEC-ios §3.5) — 오늘 순위 · 로컬 최고 · 라운드 토큰 · 점수 제출 · 공개 여부. 맥 `WorkTimerStoreMiniGame` 의
/// 흐름을 폰 세션 위에 다시 썼다(맥 스토어는 폰에서 못 쓴다 — ios-inventory §4.3).
///
/// 라운드 토큰 흐름(맥과 같다)
/// 1. **화면을 열 때 미리 받는다**(`openScreen`). 판 시작에 받으면 플래피 즉사처럼 1초 안에 끝나는 판은 왕복이 못 끝나
///    점수를 통째로 버린다. 일찍 받을수록 서버가 재는 경과가 길어져 **더 관대하다**(정직한 플레이를 못 막는다).
/// 2. 판이 시작될 때 쓸 수 있는 토큰이 없으면(선발급 실패·20분 지남) 그때 받는다. 게임을 막지 않는다(Task 로 띄운다).
/// 3. 판이 끝나면 토큰을 **로컬에서 먼저 비우고** 제출한다(한 토큰에 한 점수). 성공이든 거절이든 다음 토큰을 미리 받는다.
/// 4. 들고 있는 토큰이 쓸 만하면 다시 받지 않는다 — 다시 받으면 서버가 started_at 을 now() 로 되돌려 벌어 둔 여유가 사라진다.
/// 5. 늦게 온 토큰 응답은 버린다(`roundGeneration`). 서버는 (사용자, 게임)당 미사용 토큰을 한 행만 두고 갈아 끼운다.
/// 6. `minigame_public == false` 면 토큰도 제출도 없다(설정 문구가 약속한 "올라가지도 않아요").
///
/// 폰 규칙: 앱이 background 로 가거나 화면을 떠나면 판을 **끝낸다**(`endRound()`). 무엇을 하는지는 게임마다 다르다 —
/// 타이밍 바·플래피는 예전처럼 기록 없이 버리고, **테트리스는 여기까지의 점수로 확정해 제출한다**(까닭은
/// `GamesPlayController.endRound()` 주석: 폰에서 background 는 비용 0.05초짜리 무한 일시정지다).
/// 로그아웃(`reset`)과 화면 경합 정리(`openScreen`)는 **`abandon()` 그대로**다 — 셋의 의도가 다르다.
///
/// 제출 인편(`pendingSubmit`): 제출이 **네트워크로** 실패하면 (게임, 점수, 토큰)을 들고 있다가 앱이 다시 active 가 될 때
/// 같은 토큰으로 한 번 더 보낸다. 지금까지는 그 자리에서 점수가 그냥 사라졌다(세 게임 모두).
/// 진단: 거절 status 이름까지만 로그에 남긴다 — need_seconds·elapsed_seconds 는 화면에도 로그에도 쓰지 않는다(위조 보조 도구).
@MainActor
@Observable
package final class GamesMiniGameHub {
    /// 토큰을 새로 받는 기준(초). 서버 TTL 30분보다 넉넉히 짧다(맥 `miniGameTokenRefreshSeconds`).
    ///
    /// ⚠️ v0.3.38 부터 **게임별**이다 — 판정은 `MiniGameKind.roundTokenReuseSeconds` 한 곳에서 나온다(테트리스는 12분).
    /// 이 상수는 기존 두 게임의 값(20분)을 가리키는 별명으로 남긴다: 여기를 고쳐도 테트리스는 안 움직인다.
    package nonisolated static let tokenRefreshSeconds: TimeInterval = MiniGameKind.flappy.roundTokenReuseSeconds
    /// 첫 화면 카드(오늘 최고·순위)를 다시 읽는 간격(초).
    package nonisolated static let summaryThrottleSeconds: TimeInterval = 60

    /// 한 판의 **벽시계 상한**(초 · 폰 테트리스만). `beginRound` 가 구동기에 건넨다.
    ///
    /// 검산: 토큰 재사용 12분 + 판 15분 + 제출 여유 1분 = 28분 < 서버 TTL 30분. 그리고 15분은 시뮬 최장 판
    /// 8.7분의 1.72배라 정직한 판은 안 걸린다. 왜 필요한가: 엔진의 **고의 늘어뜨리기 상계가 24.7분**이라
    /// 12 + 24.7 = 36.7 > 30 이다 — 상한이 없으면 24분을 쌓아 올린 판이 통째로 거절된다(클램프가 아니라 거절).
    /// 사용자 스위치로 주지 않는다(2026-09-15 '자동 종료는 사용자 스위치로 주지 않는다').
    package nonisolated static let tetrisRoundLimitSeconds: TimeInterval = 15 * 60

    /// 서버가 **명시적으로 거절**한 status. 이걸 받으면 그 토큰으로는 영영 못 올리므로 제출 인편을 지운다.
    /// (`token_used` 는 여기 없다 — 그건 **성공**이다. 아래 `performSubmit` 주석.)
    ///
    /// ⚠️ `unauthorized`·`no_profile` 도 여기다. 둘은 **토큰이 아니라 호출자 쪽 거절**이라
    /// `minigame_submit_score` 가 uid·프로필 검사에서 곧장 돌아오고 30분 TTL 판정까지 가지도 않는다 —
    /// 즉 스스로 `token_expired` 로 바뀌지 않는다. 지우지 않으면 인편이 남아 **앱을 켤 때마다 영원히**
    /// 같은 토큰을 다시 보낸다(그 사이 프리페치는 A1 가드에 막혀 그 게임의 새 토큰도 못 받는다).
    /// 다만 `deadTokenStatuses` 에는 넣지 않는다 — 문구는 "점수를 못 올렸어요"(`submitRefused`)로 남긴다.
    nonisolated static let terminalSubmitStatuses: Set<String> =
        ["too_fast", "invalid", "no_token", "token_expired", "unauthorized", "no_profile"]
    /// 토큰이 죽어 **그 판은 영영 못 올리는** 거절. 문구가 "다시 해 주세요"(복구된다는 뜻)와 갈린다.
    nonisolated static let deadTokenStatuses: Set<String> = ["no_token", "token_expired"]

    nonisolated static let logger = Logger(subsystem: "aingcheck", category: "minigame")

    @ObservationIgnored package let context: MobileContext

    /// 지금 열려 있는 게임 화면(없으면 nil).
    package private(set) var activeKind: MiniGameKind?
    /// 열린 화면의 엔진 구동기. 화면마다 새로 만든다.
    package private(set) var controller: GamesPlayController?
    package private(set) var boards: [MiniGameKind: GamesMiniGameBoard] = [:]
    /// 내 순위 공개 여부(profiles.minigame_public). 이번 로그인에서 아직 모르면 공개로 본다(맥과 같다 — 컬럼 없는 서버).
    /// 한 번 안 값은 조회 실패로 바뀌지 않는다(`refreshPublic`).
    package private(set) var isPublic = true
    /// 제출 실패·판 끝남 안내 한 줄.
    package private(set) var submitNotice: String?
    /// 로컬 최고(계정별 — 관찰용 미러). 읽기는 `best(for:)`.
    package private(set) var localBest: [MiniGameKind: Int] = [:]

    // MARK: 토큰(관찰 대상 아님)
    @ObservationIgnored package private(set) var roundToken: String?
    @ObservationIgnored package private(set) var roundTokenKind: MiniGameKind?
    @ObservationIgnored package private(set) var roundTokenAt: Date?
    @ObservationIgnored package private(set) var roundGeneration = 0
    /// 지금 왕복 중인 토큰 요청의 게임(없으면 nil). 선발급이 도는 중에 판이 시작되면 **또 요청하지 않는다** —
    /// 또 보내면 서버가 started_at 을 새로 찍어 앞 요청이 벌어 둔 여유를 버린다(폰에서 화면을 열자마자 탭하는 경로).
    @ObservationIgnored package private(set) var roundTokenInFlightKind: MiniGameKind?
    /// 아직 서버가 받았다고 확인해 주지 않은 제출 한 건. **네트워크로 실패하면 남고**, 성공·명시적 거절이면 지운다.
    /// 앱이 다시 active 가 될 때 `retryPendingSubmitIfAny()` 가 **같은 토큰으로** 한 번 더 보낸다.
    @ObservationIgnored package private(set) var pendingSubmit: (kind: MiniGameKind, score: Int, token: String)?
    /// 지금 제출 왕복이 떠 있다(인편 재시도가 같은 토큰을 두 번 보내지 않게).
    @ObservationIgnored private var isSubmitting = false
    /// 출구에서 세운 안내("앱을 나가서 …")를 **비동기 제출 성공이 지우지 않게** 붙든다.
    /// 성공 갈래는 `submitNotice = nil` 인데, 그게 이 문장을 지우면 사용자에게는 판이 조용히 사라진 것처럼 보인다.
    @ObservationIgnored private var exitNoticeIsSticky = false
    @ObservationIgnored private var resetGeneration = 0
    @ObservationIgnored private var lastSummaryAt: Date = .distantPast
    /// 엔진 시드 — 화면을 열 때마다 달라야 같은 판이 반복되지 않는다(데모 고정 시계에서도).
    @ObservationIgnored private var seedCounter: UInt64 = 0

    package init(context: MobileContext) {
        self.context = context
    }

    // MARK: 화면

    /// 게임 화면이 열렸다. 오늘 순위·어제 1등·공개 여부를 읽고 **토큰을 미리 받는다**.
    package func openScreen(_ kind: MiniGameKind) {
        if activeKind == kind, controller != nil { return }
        // 화면 경합 정리는 **버리는 것**이다(`abandon()`) — 사람이 쌓아 올린 판을 끝내는 자리가 아니다.
        controller?.abandon()
        activeKind = kind
        submitNotice = nil
        exitNoticeIsSticky = false
        seedCounter &+= 1
        let seed = UInt64(truncatingIfNeeded: Int64(context.clock.now().timeIntervalSince1970 * 1000)) &+ seedCounter &* 0x9E37_79B9_7F4A_7C15
        let controller = GamesPlayController(kind: kind, seed: seed)
        controller.onStarted = { [weak self] in self?.beginRound(kind: kind) }
        controller.onFinished = { [weak self] score in self?.recordScore(kind: kind, score: score) }
        self.controller = controller
        loadLocalBest(kind)
        guard context.session.isSignedIn else { return }
        let generation = resetGeneration
        Task { [weak self] in
            // 공개 여부를 **먼저** 안다 — 끈 사람에게 토큰을 받아 두지 않는다. 그 왕복 동안 판이 시작되면 `beginRound` 가
            // (아직 공개로 보고) 토큰을 받는다: 제출은 끝날 때 다시 공개 여부를 보므로 끈 사람의 점수는 여전히 안 나간다.
            await self?.refreshPublic()
            guard let self, generation == self.resetGeneration, self.activeKind == kind else { return }
            // 인편이 남아 있으면 **먼저 밀어낸다.** 선발급은 살아 있는 인편을 보면 스스로 비켜서므로
            // (`prefetchRoundToken` 의 가드), 여기서 인편을 풀어 두지 않으면 사람이 탭할 때까지 토큰이 없다.
            // 비워지는 순간 `performSubmit` 의 꼬리가 새 토큰을 받아 주므로 대개 첫 탭 전에 준비가 끝난다.
            self.retryPendingSubmitIfAny()
            self.prefetchRoundToken(kind: kind)
            await self.loadBoard(kind, withWinner: true)
        }
    }

    /// 게임 화면을 떠났다. 진행 중인 판은 **끝낸다**(`endRound()` — 테트리스는 여기까지의 점수로 확정 제출).
    /// 토큰은 들고 있는다(재사용 나이 안에 다시 열면 그대로 쓴다).
    ///
    /// 안내 한 줄은 세우지 않는다 — 이 화면은 지금 사라지는 중이고, 다시 열면 `openScreen` 이 어차피 비운다.
    package func closeScreen(_ kind: MiniGameKind) {
        guard activeKind == kind else { return }
        controller?.endRound()
        controller = nil
        activeKind = nil
    }

    /// 앱이 background 로 간다 — 판은 끝. 기존 두 게임은 제출하지 않고(SPEC-ios §3.5),
    /// **테트리스는 여기까지의 점수로 확정 제출한다**(`GamesPlayController.endRound()`).
    package func appDidEnterBackground() {
        guard let controller else { return }
        switch controller.endRound() {
        case .none:
            return
        case .abandoned:
            submitNotice = GamesMiniGameText.endedInBackground(controller.kind)
            exitNoticeIsSticky = false
        case .confirmed:
            // 이 줄에 닿기 전에 `endRound()` 안에서 `recordScore` 가 이미 돌았다.
            //  · 제출이 떠 있으면(인편이 있으면) "여기까지 기록했어요" 가 참이다 — 비동기 성공이 못 지우게 붙든다.
            //  · 못 띄웠으면(토큰이 없어 `recordScore` 가 그 사실을 말한 경우) 그 말을 **덮지 않는다** —
            //    안 올라간 점수를 올렸다고 하는 것이 이 화면에서 제일 나쁜 거짓말이다.
            guard pendingSubmit != nil || !isPublic || !context.session.isSignedIn else { return }
            submitNotice = GamesMiniGameText.endedInBackground(controller.kind)
            exitNoticeIsSticky = pendingSubmit != nil
        }
    }

    /// 로그아웃·치명 만료. 계정에 묶인 값을 전부 비운다.
    ///
    /// 여기는 **`abandon()` 그대로**다 — 남의 계정으로 넘어가는 자리에서 앞 사람의 판을 제출하면 안 된다.
    package func reset() {
        resetGeneration &+= 1
        roundGeneration &+= 1
        controller?.abandon()
        controller = nil
        activeKind = nil
        boards = [:]
        isPublic = true
        submitNotice = nil
        exitNoticeIsSticky = false
        localBest = [:]
        roundToken = nil
        roundTokenKind = nil
        roundTokenAt = nil
        roundTokenInFlightKind = nil
        pendingSubmit = nil
        lastSummaryAt = .distantPast
    }

    // MARK: 첫 화면 카드

    /// 첫 화면이 보였다: **폰에 보이는 게임**(`MiniGameKind.phoneCases`)의 오늘 순위(카드의 "오늘 최고·순위")를 읽는다.
    /// 60초 스로틀. 안 보이는 게임까지 돌면 폰이 쓰지 않는 순위표를 60초마다 한 번씩 더 받아 온다.
    package func refreshSummariesIfStale() {
        guard context.session.isSignedIn else { return }
        let now = context.clock.now()
        guard now.timeIntervalSince(lastSummaryAt) >= Self.summaryThrottleSeconds else { return }
        lastSummaryAt = now
        for kind in MiniGameKind.phoneCases {
            loadLocalBest(kind)
            Task { [weak self] in await self?.loadBoard(kind, withWinner: false) }
        }
    }

    /// 오늘 내 순위(1부터). 순위표에 없으면 nil.
    package func myRank(_ kind: MiniGameKind) -> Int? {
        guard let me = myUserID, let index = boards[kind]?.entries.firstIndex(where: { $0.userID == me }) else { return nil }
        return index + 1
    }

    /// 오늘 내 순위표 점수(없으면 nil).
    package func myTodayBest(_ kind: MiniGameKind) -> Int? {
        guard let me = myUserID else { return nil }
        return boards[kind]?.entries.first { $0.userID == me }?.bestScore
    }

    /// 결과 카드의 "최고 N" — 로컬 최고와 오늘 내 행 중 큰 쪽(맥 허브와 같다).
    package func best(for kind: MiniGameKind) -> Int {
        max(localBest[kind] ?? 0, myTodayBest(kind) ?? 0)
    }

    // MARK: 토큰 · 제출

    /// 들고 있는 토큰이 이 게임에 **지금** 쓸 만한가.
    package func hasUsableRoundToken(for kind: MiniGameKind) -> Bool {
        guard roundToken != nil, roundTokenKind == kind, let issued = roundTokenAt else { return false }
        // 나이 기준은 **게임별**이다(테트리스 판은 길어서 12분 — MiniGameKind.roundTokenReuseSeconds 의 검산).
        return context.clock.now().timeIntervalSince(issued) < kind.roundTokenReuseSeconds
    }

    /// 토큰을 미리 받는다(화면 열기 · 제출 뒤). 쓸 만한 토큰이 있으면 다시 받지 않는다.
    /// - Parameter force: 왕복 중인 요청이 있어도 새로 받는다 — 판이 **이미 끝났는데** 토큰이 없던 자리(그 왕복은 이번 판에
    ///   늦었고, 실패로 끝나면 아무도 다시 받지 않는다). 새 요청이 나가면 앞 요청의 응답은 세대 가드가 버린다.
    package func prefetchRoundToken(kind: MiniGameKind, force: Bool = false) {
        guard isPublic, context.session.isSignedIn else { return }
        // ★ 그 게임의 **인편이 살아 있으면 받지 않는다**(force 여도). 서버는 (사용자, 게임)당 미사용 토큰을 한 행만 두고
        //   새 요청이 오면 갈아 끼운다(`minigame_rounds_one_open`) — 그래서 `requestRoundToken` 주석의
        //   "새 요청이 나가는 순간 들고 있던 것은 죽는다"가 **인편이 들고 있는 토큰에도 그대로** 걸린다.
        //   제출이 네트워크로 실패한 직후 여기서 새 토큰을 받으면, 복귀 재시도는 `no_token`(terminal)을 받고
        //   인편이 버려진다 — 인편이라는 장치의 유일한 이득이 자기 손으로 무너진다.
        //   막힌 채로 굳지 않는다: 인편은 `retryPendingSubmitIfAny()`(복귀)와 `beginRound`(새 판)가 밀어내고,
        //   비워지는 순간 `performSubmit` 의 꼬리가 여기를 다시 불러 새 토큰을 받는다.
        guard pendingSubmit?.kind != kind else { return }
        guard !hasUsableRoundToken(for: kind) else { return }
        guard force || roundTokenInFlightKind != kind else { return }
        requestRoundToken(kind: kind)
    }

    /// 판이 시작됐다(엔진 onStarted). 쓸 만한 토큰이 없을 때만 받는다 — 게임은 기다리지 않는다.
    package func beginRound(kind: MiniGameKind) {
        // 판 벽시계 상한은 **가드보다 먼저** 건다: 순위 공정성 장치라 공개 여부·로그인과 무관하다.
        // 기존 두 게임은 nil(판이 스스로 끝나거나 자동잠금이 상한이다 — `GamesStore.wantsIdleTimerDisabled`).
        //
        // ⚠️ **길이를 건넨다(절대 시각이 아니다).** 마감을 재는 축은 구동기의 `tick(at:)` 하나뿐인데 그 `now` 는
        //    `TimelineView` 가 주는 실제 벽시계다 — 여기서 `context.clock.now()` 로 찍으면 두 축이 섞여
        //    시계를 주입한 빌드(데모·테스트)에서 판이 첫 프레임에 죽는다(까닭은 `GamesPlayController.roundLimitSeconds`).
        controller?.roundLimitSeconds = kind == .tetris ? Self.tetrisRoundLimitSeconds : nil
        exitNoticeIsSticky = false
        guard isPublic, context.session.isSignedIn else { return }
        submitNotice = nil
        guard !hasUsableRoundToken(for: kind) else { return }
        // ★ 이 게임의 인편이 살아 있으면 토큰을 받는 대신 **인편부터 밀어낸다**(까닭은 `prefetchRoundToken` 의 가드).
        //   여기가 인편을 푸는 두 방아쇠 가운데 하나다(다른 하나는 복귀 `retryPendingSubmitIfAny()`).
        //   성공·명시적 거절로 비워지면 `performSubmit` 꼬리의 프리페치가 곧바로 새 토큰을 받아 준다.
        //   이번 판이 토큰 없이 시작될 수는 있다 — 그건 앞 판을 확실히 버리는 것보다 싸고, `recordScore` 가
        //   "못 올렸어요"로 사실대로 말한다.
        guard pendingSubmit?.kind != kind else {
            retryPendingSubmitIfAny()
            return
        }
        guard roundTokenInFlightKind != kind else { return }
        requestRoundToken(kind: kind)
    }

    private func requestRoundToken(kind: MiniGameKind) {
        // 들고 있던 것은 버린다 — 서버가 행을 갈아 끼우므로 새 요청이 나가는 순간 죽는다.
        roundToken = nil
        roundTokenKind = nil
        roundTokenAt = nil
        roundGeneration &+= 1
        roundTokenInFlightKind = kind
        let generation = roundGeneration
        Task { [weak self] in await self?.performStartRound(kind: kind, roundGeneration: generation) }
    }

    package func performStartRound(kind: MiniGameKind, roundGeneration requested: Int) async {
        defer { if requested == roundGeneration { roundTokenInFlightKind = nil } }
        guard context.session.isSignedIn else { return }
        let sessionGeneration = context.generation
        let service = context.service
        do {
            let response = try await context.withMobileSessionRetry { session in
                try await service.startMiniGameRound(accessToken: session.accessToken, kind: kind)
            }
            guard sessionGeneration == context.generation else { return }
            // ★ 늦게 온 응답은 버린다 — 내 뒤에 나간 요청이 있었다면 내 토큰은 이미 죽었다.
            guard requested == roundGeneration else { return }
            guard response.status == "ok", let token = response.token else {
                Self.logger.notice("round token refused status=\(response.status, privacy: .public) game=\(kind.rawValue, privacy: .public)")
                return
            }
            roundToken = token
            roundTokenKind = kind
            roundTokenAt = context.clock.now()
        } catch {
            guard requested == roundGeneration else { return }
            Self.logger.notice("round token request failed game=\(kind.rawValue, privacy: .public)")
        }
    }

    /// 유효하게 끝난 판(엔진 onFinished). 범위 밖은 버리고, 로컬 최고를 올리고, 공개면 토큰과 함께 올린다.
    package func recordScore(kind: MiniGameKind, score: Int) {
        guard score >= 0, score <= kind.maxScore else { return }
        raiseLocalBest(kind, to: score)
        guard isPublic, context.session.isSignedIn else { return }
        guard let token = roundToken, roundTokenKind == kind else {
            Self.logger.notice("submit skipped — no token game=\(kind.rawValue, privacy: .public)")
            submitNotice = GamesMiniGameText.submitFailedConnection
            prefetchRoundToken(kind: kind, force: true)
            return
        }
        // 한 토큰에 한 점수 — 여기서 비워 두면 같은 토큰이 두 번 나가지 않는다.
        // 대신 **인편**(pendingSubmit)에 적는다: 네트워크로 실패해도 점수가 그 자리에서 사라지지 않게.
        roundToken = nil
        roundTokenKind = nil
        roundTokenAt = nil
        // ★ 인편 칸은 하나뿐이다. 밀려나는 앞 판을 **조용히 버리지 않는다** — 예전에는 그대로 덮어써서
        //   앞 판 점수가 재시도 한 번 없이 사라졌고, 그 판의 실패 안내마저 `beginRound` 의 `submitNotice = nil` 이
        //   이미 지운 뒤였다(사용자에게는 판이 통째로 증발한 것으로 보인다).
        if let superseded = pendingSubmit, superseded.token != token {
            sendSupersededPending(superseded)
        }
        pendingSubmit = (kind: kind, score: score, token: token)
        Task { [weak self] in await self?.performSubmit(kind: kind, score: score, token: token) }
    }

    /// 인편 칸에서 밀려나는 제출을 **마지막으로 한 번** 보낸다(버리기 전에).
    ///
    /// 왜 그냥 버리지 않는가: 네트워크 실패는 "요청이 못 갔다"만이 아니라 **"응답만 유실됐다"** 일 수도 있다.
    /// 후자면 점수는 이미 올라가 있고 서버가 `token_used` 로 답한다 — 그때 진짜 최고와 순위를 다시 읽어 온다.
    /// 전자면 새 토큰이 그 행을 갈아 끼웠으므로 `no_token` 이 오고, 잃는 것은 왕복 한 번뿐이다.
    ///
    /// 왜 `performSubmit` 을 재활용하지 않는가: 그쪽은 **`submitNotice` 를 쓴다.** 그 한 줄은 지금 막 끝난
    /// 이 판의 것이고, 밀려난 앞 판의 거절 문구가 그 자리를 덮으면 사용자는 **엉뚱한 판**에 대한 말을 읽는다.
    /// 그래서 여기서는 화면에 한 글자도 쓰지 않고 로컬 최고·순위만 고친다(인편 칸도 건드리지 않는다 —
    /// 이 시점의 주인은 새 판이다).
    private func sendSupersededPending(_ superseded: (kind: MiniGameKind, score: Int, token: String)) {
        Self.logger.notice("pending submit superseded — sending once more game=\(superseded.kind.rawValue, privacy: .public)")
        let sessionGeneration = context.generation
        let generation = resetGeneration
        let service = context.service
        Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await context.withMobileSessionRetry { session in
                    try await service.submitMiniGameScore(accessToken: session.accessToken, kind: superseded.kind,
                                                          score: superseded.score, token: superseded.token)
                }
                guard sessionGeneration == self.context.generation, generation == self.resetGeneration else { return }
                // `token_used` 는 여기서도 성공이다(위 이유 그대로 — 응답만 유실된 첫 제출).
                guard response.status == "ok" || response.status == "token_used" else {
                    Self.logger.notice("superseded submit refused status=\(response.status, privacy: .public) game=\(superseded.kind.rawValue, privacy: .public)")
                    return
                }
                if let best = response.bestScore { self.raiseLocalBest(superseded.kind, to: best) }
                await self.loadBoard(superseded.kind, withWinner: false)
            } catch {
                Self.logger.notice("superseded submit failed (network) game=\(superseded.kind.rawValue, privacy: .public)")
            }
        }
    }

    /// 앱이 다시 active 가 됐다 — 서버가 받았다고 확인해 주지 않은 제출이 있으면 **같은 토큰으로** 한 번 더.
    /// 같은 토큰이라 두 번 올라가지 않는다(서버가 `token_used` 로 돌려주고, 그건 아래에서 성공으로 접는다).
    package func retryPendingSubmitIfAny() {
        guard let pending = pendingSubmit, !isSubmitting else { return }
        guard isPublic, context.session.isSignedIn else { return }
        Task { [weak self] in
            await self?.performSubmit(kind: pending.kind, score: pending.score, token: pending.token)
        }
    }

    package func performSubmit(kind: MiniGameKind, score: Int, token: String) async {
        guard context.session.isSignedIn else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        let sessionGeneration = context.generation
        let generation = resetGeneration
        let service = context.service
        do {
            let response = try await context.withMobileSessionRetry { session in
                try await service.submitMiniGameScore(accessToken: session.accessToken, kind: kind, score: score, token: token)
            }
            guard sessionGeneration == context.generation, generation == resetGeneration else { return }
            // ★ `token_used` 는 **성공이다.** 서버는 제출이 성공한 순간 그 토큰에 used_at 을 찍고, 이미 쓴 토큰에는
            //   `token_used` 를 돌려준다. 즉 이 응답을 받는 경우는 **응답만 유실된 첫 제출의 재시도**뿐이고,
            //   그때 점수는 이미 올라가 있다. 이걸 거절로 그리면 올라간 점수를 "못 올렸어요"라고 말하는 거짓말이 된다.
            if response.status == "ok" || response.status == "token_used" {
                if let best = response.bestScore { raiseLocalBest(kind, to: best) }
                clearPendingSubmit(token: token)
                // 출구에서 세운 안내("앱을 나가서 …")는 제출과 무관한 사실이라 지우지 않는다.
                if !exitNoticeIsSticky { submitNotice = nil }
                // 순위 재조회는 **화면을 떠난 뒤에도** 한다(activeKind 로 막으면 뒤로가기로 끝낸 판이 반영되지 않는다).
                await loadBoard(kind, withWinner: false)
            } else {
                Self.logger.notice("submit refused status=\(response.status, privacy: .public) game=\(kind.rawValue, privacy: .public)")
                // 토큰이 죽은 거절은 **그 판이 영영 못 올라간다** — "다시 해 주세요"(복구된다는 뜻)와 문장을 가른다.
                submitNotice = Self.deadTokenStatuses.contains(response.status)
                    ? GamesMiniGameText.submitTokenDead
                    : GamesMiniGameText.submitRefused
                exitNoticeIsSticky = false
                if Self.terminalSubmitStatuses.contains(response.status) { clearPendingSubmit(token: token) }
            }
            prefetchRoundToken(kind: kind)
        } catch {
            if case .cancelled = AuthErrorRules.classify(error) { return }
            guard sessionGeneration == context.generation, generation == resetGeneration else { return }
            Self.logger.notice("submit failed (network) game=\(kind.rawValue, privacy: .public)")
            // 네트워크 실패는 인편을 **남긴다** — 복귀 때 같은 토큰으로 한 번 더 보낸다.
            submitNotice = GamesMiniGameText.submitFailedConnection
            exitNoticeIsSticky = false
            prefetchRoundToken(kind: kind)
        }
    }

    /// 이 토큰의 인편만 지운다(그 사이 새 판이 인편을 갈아 끼웠으면 건드리지 않는다).
    private func clearPendingSubmit(token: String) {
        guard pendingSubmit?.token == token else { return }
        pendingSubmit = nil
    }

    // MARK: 조회

    /// 공개 여부를 읽는다(설정은 나 탭이 바꾼다 — 화면을 열 때마다 다시 읽는다).
    ///
    /// - 서버가 답했다: 그 값. 행·컬럼이 없어 값이 없으면(nil) 공개(맥과 같다 — 컬럼 없는 서버).
    /// - 표·함수가 아직 없는 서버(`databaseSchemaMissing`): 공개.
    /// - **그 밖의 실패(오프라인·5xx·만료)는 아는 값을 그대로 둔다** — 예전에는 `try?` 가 실패를 nil 로 바꿔 "모름 = 공개"로
    ///   덮었고, 순위 공개를 끈 사람의 점수가 조회 한 번 실패 뒤 서버로 나갔다(games-verify PROBE-1). 맥
    ///   `miniGamePublicLoaded` 도 실패는 값을 바꾸지 않는다.
    package func refreshPublic() async {
        guard context.session.isSignedIn, let userID = context.session.session?.userID else { return }
        let sessionGeneration = context.generation
        let generation = resetGeneration
        let service = context.service
        let resolved: Bool
        do {
            let value = try await context.withMobileSessionRetry { session in
                try await service.fetchMiniGamePublic(accessToken: session.accessToken, userID: userID)
            }
            resolved = value ?? true
        } catch SupabaseWorkServiceError.databaseSchemaMissing {
            resolved = true
        } catch {
            if case .cancelled = AuthErrorRules.classify(error) { return }
            guard sessionGeneration == context.generation, generation == resetGeneration else { return }
            let kept = isPublic
            Self.logger.notice("minigame public lookup failed — keeping isPublic=\(kept, privacy: .public)")
            return
        }
        guard sessionGeneration == context.generation, generation == resetGeneration else { return }
        if isPublic != resolved { isPublic = resolved }
        if !resolved {
            // 꺼져 있으면 들고 있는 토큰은 쓸 일이 없다.
            roundToken = nil
            roundTokenKind = nil
            roundTokenAt = nil
        }
    }

    /// 오늘 순위(+어제 1등). 두 조회는 독립 실패다(맥과 같다).
    package func loadBoard(_ kind: MiniGameKind, withWinner: Bool) async {
        guard context.session.isSignedIn else { return }
        let sessionGeneration = context.generation
        let generation = resetGeneration
        let service = context.service
        var state = boards[kind] ?? GamesMiniGameBoard()
        if !state.loading {
            state.loading = true
            state.failed = false
            boards[kind] = state
        }
        do {
            let entries = try await context.withMobileSessionRetry { session in
                try await service.fetchMiniGameBoard(accessToken: session.accessToken, kind: kind, day: nil)
            }
            guard sessionGeneration == context.generation, generation == resetGeneration else { return }
            var next = boards[kind] ?? GamesMiniGameBoard()
            next.entries = entries.sortedForMiniGameBoard()
            next.loaded = true
            next.loading = false
            next.failed = false
            if boards[kind] != next { boards[kind] = next }
            if let me = myUserID, let mine = next.entries.first(where: { $0.userID == me }) {
                raiseLocalBest(kind, to: mine.bestScore)
            }
        } catch {
            if case .cancelled = AuthErrorRules.classify(error) { return }
            guard sessionGeneration == context.generation, generation == resetGeneration else { return }
            var next = boards[kind] ?? GamesMiniGameBoard()
            next.loading = false
            if case SupabaseWorkServiceError.databaseSchemaMissing = error {
                // 표·함수가 아직 없는 서버: 실패가 아니라 "아직 기록이 없다"로 조용히 접는다(맥과 같다).
                next.loaded = true
            } else {
                next.failed = true
            }
            boards[kind] = next
            return
        }
        guard withWinner else { return }
        let winner = try? await context.withMobileSessionRetry { session in
            try await service.fetchMiniGameYesterdayWinner(accessToken: session.accessToken, kind: kind)
        }
        guard sessionGeneration == context.generation, generation == resetGeneration else { return }
        let resolved = winner
        if boards[kind]?.yesterdayWinner != resolved { boards[kind]?.yesterdayWinner = resolved }
    }

    // MARK: 로컬 최고

    /// 로컬 최고 키 — **계정별**(같은 폰을 다른 계정이 쓰면 남의 최고를 물려받지 않는다). 공용 suite 에 둔다.
    package nonisolated static func bestKey(userID: String?, kind: MiniGameKind) -> String {
        "aing.minigame.best.\(userID ?? "local").\(kind.rawValue)"
    }

    private var myUserID: String? { context.session.session?.userID.lowercased() }

    private func loadLocalBest(_ kind: MiniGameKind) {
        let stored = max(0, context.storage.defaults.integer(forKey: Self.bestKey(userID: myUserID, kind: kind)))
        if localBest[kind] != stored { localBest[kind] = stored }
    }

    private func raiseLocalBest(_ kind: MiniGameKind, to score: Int) {
        let key = Self.bestKey(userID: myUserID, kind: kind)
        let current = max(0, context.storage.defaults.integer(forKey: key))
        if score > current { context.storage.defaults.set(score, forKey: key) }
        let resolved = max(current, score)
        if localBest[kind] != resolved { localBest[kind] = resolved }
    }
}
