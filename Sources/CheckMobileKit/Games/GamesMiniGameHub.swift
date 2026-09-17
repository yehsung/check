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
/// 폰 규칙: 앱이 background 로 가면 판을 끝내고 **제출하지 않는다**(`appDidEnterBackground`).
/// 진단: 거절 status 이름까지만 로그에 남긴다 — need_seconds·elapsed_seconds 는 화면에도 로그에도 쓰지 않는다(위조 보조 도구).
@MainActor
@Observable
package final class GamesMiniGameHub {
    /// 토큰을 새로 받는 기준(초). 서버 TTL 30분보다 넉넉히 짧다(맥 `miniGameTokenRefreshSeconds`).
    package nonisolated static let tokenRefreshSeconds: TimeInterval = 20 * 60
    /// 첫 화면 카드(오늘 최고·순위)를 다시 읽는 간격(초).
    package nonisolated static let summaryThrottleSeconds: TimeInterval = 60

    nonisolated static let logger = Logger(subsystem: "aingcheck", category: "minigame")

    @ObservationIgnored package let context: MobileContext

    /// 지금 열려 있는 게임 화면(없으면 nil).
    package private(set) var activeKind: MiniGameKind?
    /// 열린 화면의 엔진 구동기. 화면마다 새로 만든다.
    package private(set) var controller: GamesPlayController?
    package private(set) var boards: [MiniGameKind: GamesMiniGameBoard] = [:]
    /// 내 순위 공개 여부(profiles.minigame_public). 모르면 공개로 본다(맥과 같다 — 컬럼 없는 서버).
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
        controller?.abandon()
        activeKind = kind
        submitNotice = nil
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
            self.prefetchRoundToken(kind: kind)
            await self.loadBoard(kind, withWinner: true)
        }
    }

    /// 게임 화면을 떠났다. 진행 중인 판은 기록 없이 끝낸다. 토큰은 들고 있는다(20분 안에 다시 열면 그대로 쓴다).
    package func closeScreen(_ kind: MiniGameKind) {
        guard activeKind == kind else { return }
        controller?.abandon()
        controller = nil
        activeKind = nil
    }

    /// 앱이 background 로 간다 — 판은 끝, 제출하지 않는다(SPEC-ios §3.5).
    package func appDidEnterBackground() {
        guard let controller, controller.abandon() else { return }
        submitNotice = GamesMiniGameText.endedInBackground
    }

    /// 로그아웃·치명 만료. 계정에 묶인 값을 전부 비운다.
    package func reset() {
        resetGeneration &+= 1
        roundGeneration &+= 1
        controller?.abandon()
        controller = nil
        activeKind = nil
        boards = [:]
        isPublic = true
        submitNotice = nil
        localBest = [:]
        roundToken = nil
        roundTokenKind = nil
        roundTokenAt = nil
        roundTokenInFlightKind = nil
        lastSummaryAt = .distantPast
    }

    // MARK: 첫 화면 카드

    /// 첫 화면이 보였다: 두 게임의 오늘 순위(카드의 "오늘 최고·순위")를 읽는다. 60초 스로틀.
    package func refreshSummariesIfStale() {
        guard context.session.isSignedIn else { return }
        let now = context.clock.now()
        guard now.timeIntervalSince(lastSummaryAt) >= Self.summaryThrottleSeconds else { return }
        lastSummaryAt = now
        for kind in MiniGameKind.allCases {
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
        return context.clock.now().timeIntervalSince(issued) < Self.tokenRefreshSeconds
    }

    /// 토큰을 미리 받는다(화면 열기 · 제출 뒤). 쓸 만한 토큰이 있으면 다시 받지 않는다.
    /// - Parameter force: 왕복 중인 요청이 있어도 새로 받는다 — 판이 **이미 끝났는데** 토큰이 없던 자리(그 왕복은 이번 판에
    ///   늦었고, 실패로 끝나면 아무도 다시 받지 않는다). 새 요청이 나가면 앞 요청의 응답은 세대 가드가 버린다.
    package func prefetchRoundToken(kind: MiniGameKind, force: Bool = false) {
        guard isPublic, context.session.isSignedIn else { return }
        guard !hasUsableRoundToken(for: kind) else { return }
        guard force || roundTokenInFlightKind != kind else { return }
        requestRoundToken(kind: kind)
    }

    /// 판이 시작됐다(엔진 onStarted). 쓸 만한 토큰이 없을 때만 받는다 — 게임은 기다리지 않는다.
    package func beginRound(kind: MiniGameKind) {
        guard isPublic, context.session.isSignedIn else { return }
        submitNotice = nil
        guard !hasUsableRoundToken(for: kind), roundTokenInFlightKind != kind else { return }
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
        roundToken = nil
        roundTokenKind = nil
        roundTokenAt = nil
        Task { [weak self] in await self?.performSubmit(kind: kind, score: score, token: token) }
    }

    package func performSubmit(kind: MiniGameKind, score: Int, token: String) async {
        guard context.session.isSignedIn else { return }
        let sessionGeneration = context.generation
        let generation = resetGeneration
        let service = context.service
        do {
            let response = try await context.withMobileSessionRetry { session in
                try await service.submitMiniGameScore(accessToken: session.accessToken, kind: kind, score: score, token: token)
            }
            guard sessionGeneration == context.generation, generation == resetGeneration else { return }
            if response.status == "ok" {
                if let best = response.bestScore { raiseLocalBest(kind, to: best) }
                submitNotice = nil
                if activeKind == kind { await loadBoard(kind, withWinner: false) }
            } else {
                Self.logger.notice("submit refused status=\(response.status, privacy: .public) game=\(kind.rawValue, privacy: .public)")
                submitNotice = GamesMiniGameText.submitRefused
            }
            prefetchRoundToken(kind: kind)
        } catch {
            if case .cancelled = AuthErrorRules.classify(error) { return }
            guard sessionGeneration == context.generation, generation == resetGeneration else { return }
            Self.logger.notice("submit failed (network) game=\(kind.rawValue, privacy: .public)")
            submitNotice = GamesMiniGameText.submitFailedConnection
            prefetchRoundToken(kind: kind)
        }
    }

    // MARK: 조회

    /// 공개 여부를 읽는다(설정은 나 탭이 바꾼다 — 화면을 열 때마다 다시 읽는다). 모르면 공개.
    package func refreshPublic() async {
        guard context.session.isSignedIn, let userID = context.session.session?.userID else { return }
        let sessionGeneration = context.generation
        let generation = resetGeneration
        let service = context.service
        let value = try? await context.withMobileSessionRetry { session in
            try await service.fetchMiniGamePublic(accessToken: session.accessToken, userID: userID)
        }
        guard sessionGeneration == context.generation, generation == resetGeneration else { return }
        let resolved = value ?? true
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
