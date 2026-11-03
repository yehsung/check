import Foundation

// 아잉 뒤집기 관전 — 스토어 확장과 값 타입. 계약은 설계서 FLIP/SPEC.md §3.4(reversi_watch · reversi_watch_live) · §3.6 · §4.4.
// 틀은 체스 `ChessStoreWatch`: 관전 2초 폴링 · 관전 세대 · watch_live 가 없으면 watch 로 한 번 접기
// (`spectatorCountUnavailable`) · watch 도 없으면 `watchUnavailable`(관전 잠금은 이 깃발 하나로만).
// 관전은 phase 가 아니라 로비 안의 `spectating != nil` 로 갈린다. 내 판이 서면 관전은 내려간다.

/// 지금 보고 있는 남의 판. 첫 ok 응답 전에는 로비 카드에서 빌린 얼굴·판돈만 있다.
package nonisolated struct ReversiSpectating: Identifiable, Equatable, Sendable {
    /// match id 소문자.
    package let id: String
    /// 로비 카드에서 빌린 두 얼굴(a·b 순서, **색 모름**). 씨앗을 못 찾았으면 비어 있다.
    package var faces: [ReversiUser]
    /// 판돈. 씨앗이 없으면 nil 이고 응답의 `match.stake` 가 채운다.
    package var stake: Int?
    /// 서버가 말한 흑·백. **첫 ok 응답 전에는 nil** — 이 둘이 서기 전에는 색 배지를 그리지 않는다.
    package var blackUser: ReversiUser?
    package var whiteUser: ReversiUser?
    package var board: ReversiBoard
    package var moveCount: Int
    /// 내가 반영한 마지막 수 번호. 다음 요청의 `p_since_seq` 다.
    package var appliedSeq: Int
    package var plies: [ReversiPly]
    package var lastStoneIdx: Int?
    package var autoStones: Set<Int>
    /// 끝나면 nil.
    package var turn: ReversiColor?
    package var turnStartedAt: Date?
    /// 표시 마감(차례 시작 + 30초). 끝났으면 nil.
    package var deadline: Date?
    package var counts: ReversiCounts
    package var score: ReversiScore?
    package var result: ReversiResult?
    package var endReason: ReversiEndReason?
    /// 이긴 색. 끝났는데 nil 이면 무승부다.
    package var winner: ReversiColor?
    package var blackAutoStreak: Int
    package var whiteAutoStreak: Int
    package var startedAt: Date?
    package var isFinished: Bool
    /// 관전자 수(watch_live 만 채운다).
    package var watchers: Int

    package init(
        id: String, faces: [ReversiUser] = [], stake: Int? = nil, blackUser: ReversiUser? = nil,
        whiteUser: ReversiUser? = nil, board: ReversiBoard = .start, moveCount: Int = 0, appliedSeq: Int = 0,
        plies: [ReversiPly] = [], lastStoneIdx: Int? = nil, autoStones: Set<Int> = [], turn: ReversiColor? = nil,
        turnStartedAt: Date? = nil, deadline: Date? = nil, counts: ReversiCounts? = nil, score: ReversiScore? = nil,
        result: ReversiResult? = nil, endReason: ReversiEndReason? = nil, winner: ReversiColor? = nil,
        blackAutoStreak: Int = 0, whiteAutoStreak: Int = 0, startedAt: Date? = nil, isFinished: Bool = false,
        watchers: Int = 0
    ) {
        self.id = id
        self.faces = faces
        self.stake = stake
        self.blackUser = blackUser
        self.whiteUser = whiteUser
        self.board = board
        self.moveCount = moveCount
        self.appliedSeq = appliedSeq
        self.plies = plies
        self.lastStoneIdx = lastStoneIdx
        self.autoStones = autoStones
        self.turn = turn
        self.turnStartedAt = turnStartedAt
        self.deadline = deadline
        self.counts = counts ?? board.counts
        self.score = score
        self.result = result
        self.endReason = endReason
        self.winner = winner
        self.blackAutoStreak = blackAutoStreak
        self.whiteAutoStreak = whiteAutoStreak
        self.startedAt = startedAt
        self.isFinished = isFinished
        self.watchers = watchers
    }
}

/// 관전·순위 갈래의 관찰 대상이 아닌 장부(스토어 본문에 한 줄로 붙는다 — 저장 프로퍼티는 확장에 못 둔다).
///
/// 이름이 `reset` 이 아니라 `clear` 인 까닭: 소스 계약 시험이 한 파일에서 `func reset()` 의 **첫 등장**을 스토어 것으로
/// 잡는다 — 같은 이름을 앞에 두면 그 시험이 이 몸통을 읽는다.
@MainActor
package final class ReversiWatchRuntime {
    package var lastWatchRequestAt: Date = .distantPast
    package var watchInFlight = false
    /// 조회 중에 또 조회할 이유가 생겼다 — 끝나면 한 번 더 돈다.
    package var watchAgain = false
    /// 다음 조회 한 번을 `p_since_seq = 0` 으로 띄운다(수 번호에 구멍이 났다). 내리는 것은 **그 전체를 실어 온 응답**이다.
    package var watchWantsFull = false
    package private(set) var watchGeneration = 0
    /// 연속 실패 횟수(throw 경로 — 5xx·오프라인). 문턱을 넘으면 관전을 내리고 안내 한 줄을 남긴다.
    package var watchFailureStreak = 0
    package var lastRankingRequestAt: Date = .distantPast
    package var rankingInFlight = false

    package init() {}

    @discardableResult
    package func bumpWatchGeneration() -> Int {
        watchGeneration &+= 1
        return watchGeneration
    }

    /// 전부 초기값 + 세대 한 번 올림(로그아웃·계정 전환 — 앞 계정의 늦은 응답을 버린다).
    package func clear() {
        lastWatchRequestAt = .distantPast
        watchInFlight = false
        watchAgain = false
        watchWantsFull = false
        watchFailureStreak = 0
        lastRankingRequestAt = .distantPast
        rankingInFlight = false
        bumpWatchGeneration()
    }
}

extension ReversiStore {
    // MARK: 읽기

    /// 내 user id(소문자). 세션이 없으면 nil.
    package var myUserID: String? { host?.session?.userID.lowercased() }

    /// 로비 "지금 대결 중" 카드가 내 판인가([관전] 칩 대신 "내 판" 캡션).
    package func isMine(_ live: ReversiLiveMatch) -> Bool {
        guard let mine = myUserID else { return false }
        return live.a.id == mine || live.b.id == mine
    }

    /// 관전 조회가 **지금** 나가도 되는가 — 관전 스위치 + 창이 보이고 안 가려짐 + 세션.
    package var canPollSpectatorFeatures: Bool {
        spectatorFeaturesEnabled && isWindowVisible && !isWindowOccluded && host?.session != nil
    }

    /// 순위 조회가 **지금** 나가도 되는가 — 순위 스위치(관전과 **따로**) + 창 + 세션.
    package var canPollRanking: Bool {
        rankingEnabled && isWindowVisible && !isWindowOccluded && host?.session != nil
    }

    /// 지금 관전 폴링이 돌아야 하는가: 관전 중 + 안 끝남 + 로비 화면 + 스위치·창·세션.
    package var shouldPollWatch: Bool {
        guard let watch = spectating, !watch.isFinished else { return false }
        return phase == .lobby && canPollSpectatorFeatures
    }

    // MARK: 진입 · 이탈

    /// 로비 "지금 대결 중" 줄의 [관전]. 로비 카드의 두 얼굴을 씨앗으로 관전 상태를 세우고, 창이 보이면 곧바로 한 번 읽는다.
    /// 내 판이 진행 중(1:1·AI)이거나 결과 화면이면 아무것도 하지 않는다 — 관전 화면은 로비 자리에 선다.
    /// 누른 줄이 **내 판**(진행 판 id · 줄에 내가 있다)이면 관전 대신 그 판을 읽어 연다.
    package func startWatching(matchID rawID: String) {
        let id = rawID.lowercased()
        guard spectatorFeaturesEnabled, !id.isEmpty, !ReversiAIGame.isAIMatchID(id),
              host?.session != nil else { return }
        if let current = match, !current.isFinished { return }
        guard phase == .lobby else { return }
        // ★ 내 판이다(서버가 진행 중이라 말한 판 · 로비 줄에 내가 있다) — 입력 없는 관전 화면이 아니라 **내 판**을 다시 읽어 연다.
        //   state 읽기가 실패해 로비에 머문 순간의 줄이다. 관전 생존 신호도 안 보낸다(상대 화면 관전자 수에 내가 잡히지 않게).
        let listedAsMine = liveMatches.first(where: { $0.id == id }).map { isMine($0) } ?? false
        if id == activeMatchID || listedAsMine {
            Task { [weak self] in await self?.refreshMatch(id: id) }
            return
        }
        if spectating?.id == id { return }
        // ★ 문 앞에서 막는다 — 404 뒤 `stopWatching()` 이 비우므로 재진입 가드가 다시 통과한다. 잠금은 순위 주기가 풀어 준다.
        guard !watchUnavailable else {
            setNotice(ReversiNoticeText.unavailable)
            return
        }
        let seed: ReversiSpectating
        if let live = liveMatches.first(where: { $0.id == id }) {
            seed = ReversiSpectating(id: id, faces: [live.a, live.b], stake: live.stake, startedAt: live.startedAt)
        } else {
            // 로비 30초 사이 목록에서 빠진 판을 눌렀다 — 얼굴 없는 같은 로딩 상태로 들어가고 응답이 채운다.
            seed = ReversiSpectating(id: id)
        }
        resetWatchRuntime()
        clearWatchNotice()
        spectating = seed
        if canPollSpectatorFeatures {
            Task { [weak self] in await self?.refreshWatch() }
        }
    }

    /// 관전 화면의 [나가기](로비로). 관전을 내리고 목록·순위를 새로 읽는다.
    package func leaveWatch() {
        stopWatching()
        guard host?.session != nil else { return }
        Task { [weak self] in
            guard let self else { return }
            await self.refreshLobby()
            await self.refreshRanking()
        }
    }

    /// 창 닫기·초기화로 관전을 조용히 내린다(문구·요청 없음). 세대를 올려 나가 있던 응답을 버린다.
    package func stopWatching() {
        resetWatchRuntime()
        if spectating != nil { spectating = nil }
        if spectatorCount != 0 { spectatorCount = 0 }
        if let current = flip, current.matchID != match?.id { clearFlip() }
    }

    /// 세대 올림 + 장부 초기값. 앞 판의 in-flight 깃발이 남으면 새 판의 첫 조회가 "도는 중" 으로 합쳐져 영영 안 나간다.
    private func resetWatchRuntime() {
        let runtime = watchRuntime
        runtime.bumpWatchGeneration()
        runtime.watchInFlight = false
        runtime.watchAgain = false
        runtime.watchWantsFull = false
        runtime.watchFailureStreak = 0
        runtime.lastWatchRequestAt = .distantPast
    }

    /// 관전이 남긴 안내(못 보는 판·준비 중·연결)는 새 관전에 들어갈 때 걷는다.
    private func clearWatchNotice() {
        let mine: Set<String> = [ReversiNoticeText.watchGone, ReversiNoticeText.unavailable,
                                 ReversiNoticeText.checkConnection]
        if let notice, mine.contains(notice) { setNotice(nil) }
    }

    // MARK: 조회

    /// 관전 판 한 번 조회. 도는 중에 또 불리면 뒤따르는 한 번으로 합친다. 세대·판 id 두 자물쇠를 지난 응답만 `applyWatch` 로.
    package func refreshWatch() async {
        guard spectatorFeaturesEnabled, host?.session != nil, let watched = spectating else { return }
        let runtime = watchRuntime
        if runtime.watchInFlight {
            runtime.watchAgain = true
            return
        }
        runtime.watchInFlight = true
        let generation = runtime.watchGeneration
        let resetMark = resetGeneration
        let id = watched.id
        repeat {
            runtime.watchAgain = false
            let since = runtime.watchWantsFull ? 0 : (spectating?.appliedSeq ?? 0)
            runtime.lastWatchRequestAt = clock()
            let result = await watchFetch(matchID: id, sinceSeq: since)
            // 세대가 밀렸으면(나가기·판 전환·내 판·로그아웃) 장부는 그쪽이 이미 비웠다 — 아무것도 건드리지 않는다.
            guard generation == runtime.watchGeneration, resetMark == resetGeneration else { return }
            switch result {
            case .success(let response)?:
                applyWatch(response, requestedSince: since)
            case .failure(let error)?:
                noteWatchFailure(error)
            case nil:
                break
            }
            guard generation == runtime.watchGeneration else { return }
        } while runtime.watchAgain && spectating != nil
        runtime.watchInFlight = false
    }

    /// 관전 한 번 — `reversi_watch_live`(관전 + 관전자 수)를 먼저 부르고, 서버에 그 함수가 아직 없으면 `reversi_watch` 로
    /// **한 번 접어** 같은 바퀴 안에서 다시 부른다. 접힘은 이 로그인 동안 한 번만 판정한다(`spectatorCountUnavailable`).
    /// ★ 이 실패는 `watchUnavailable`(관전 입구 잠금)도 연속 실패도 **건드리지 않는다** — 잃는 것은 숫자 한 칸뿐이다.
    private func watchFetch(matchID: String, sinceSeq: Int) async -> Result<ReversiActionResponse, any Error>? {
        if !spectatorCountUnavailable {
            let live = await perform({
                try await $0.reversiWatchLive(accessToken: $1, matchID: matchID, sinceSeq: sinceSeq)
            })
            guard case .failure(let error)? = live, isSchemaMissing(error) else { return live }
            Self.logger.notice("reversi_watch_live missing — folding to reversi_watch")
            spectatorCountUnavailable = true
        }
        return await perform({ try await $0.reversiWatch(accessToken: $1, matchID: matchID, sinceSeq: sinceSeq) })
    }

    /// 관전 응답을 화면 값으로 옮긴다. 관전 중이 아니거나 **다른 판** 응답이면 아무것도 바꾸지 않는다(둘째 자물쇠).
    package func applyWatch(_ response: ReversiActionResponse, requestedSince: Int = 0) {
        guard let current = spectating else { return }
        switch response.status {
        case .ok:
            guard let payload = response.state, let row = payload.match else {
                noteWatchFailure(nil)        // ok 인데 판이 없다 — 모르는 모양은 실패로 센다(연속되면 내린다)
                return
            }
            guard row.id?.lowercased() == current.id else { return }
            noteServerNow(payload.serverNowMs)
            // 관전이 실제로 왔다 — 서버에 함수가 있다. 잠겼던 칩을 여기서 연다.
            if watchUnavailable { watchUnavailable = false }
            let status = row.matchStatus
            guard status == .active || status == .finished else {
                // 서버 계약상 여기로 못 온다(pending 은 not_found 다). 와도 판이 아니다 — not_found 와 같은 길.
                stopWatching()
                setNotice(ReversiNoticeText.watchGone)
                return
            }
            let inMatch = status == .active
            let black = playerUser(payload.blackUser, inMatch: inMatch)
                ?? knownUser(id: row.black, in: current) ?? current.blackUser
            let white = playerUser(payload.whiteUser, inMatch: inMatch)
                ?? knownUser(id: row.white, in: current) ?? current.whiteUser
            let turnStartedAt = deviceDate(serverMs: row.turnStartedMs)
            let deadline = deviceDate(serverMs: row.deadlineMs)
                ?? turnStartedAt?.addingTimeInterval(TimeInterval(turnSeconds))
            let startedAt = deviceDate(serverMs: row.startedMs) ?? current.startedAt
            guard let mapped = Self.spectateState(
                applying: payload, to: current, requestedSince: requestedSince,
                black: black, white: white, turnStartedAt: turnStartedAt, deadline: deadline, startedAt: startedAt
            ) else { return }
            let runtime = watchRuntime
            runtime.watchFailureStreak = 0   // 판을 실은 응답 = 연결이 살아 있다
            if mapped.needsFull {
                // 수 번호에 구멍 — 판은 문자열이 권위라 멀쩡하지만 **기록**이 구멍 난 채로는 그리지 않는다.
                runtime.watchWantsFull = true
                runtime.watchAgain = true
                return
            }
            if requestedSince == 0 { runtime.watchWantsFull = false }
            // 나 말고 몇 명이 이 판을 보고 있는가(watch_live 만 채운다 — 옛 길로 접히면 0 이고 화면은 아무것도 안 그린다).
            if spectatorCount != mapped.state.watchers { spectatorCount = mapped.state.watchers }
            if spectating != mapped.state { spectating = mapped.state }
            // 관전도 같은 뒤집기 그림을 쓴다 — 창이 보일 때 · 돌 한 수(+ 패스)만 나아갔을 때만.
            if mapped.state.moveCount != current.moveCount {
                if isWindowVisible, !isWindowOccluded,
                   let made = ReversiFlipAnimation.make(
                       matchID: current.id, previousMoveCount: current.moveCount,
                       nextMoveCount: mapped.state.moveCount, plies: mapped.state.plies, at: clock()) {
                    beginFlip(made)
                } else if flip?.matchID == current.id {
                    clearFlip()
                }
            }
        case .notFound:
            // 끝난 지 오래된 판·없는 판·숨김 격리 — 서버는 있다/없다를 가르지 않는다.
            stopWatching()
            setNotice(ReversiNoticeText.watchGone)
        case .unsupportedClient:
            stopWatching()
            noteUpdateRequired()
        default:
            Self.logger.notice("watch refused status=\(response.status.rawValue, privacy: .public)")
            noteWatchFailure(nil)            // unauthorized·모르는 status 도 연속이면 내린다
        }
    }

    /// 판의 두 사람 중 서버 행이 빠진 쪽을 id 로 찾는다: 씨앗 얼굴(로비 카드) → 로비 목록.
    private func knownUser(id rawID: String?, in current: ReversiSpectating) -> ReversiUser? {
        guard let id = rawID?.lowercased(), !id.isEmpty else { return nil }
        return current.faces.first { $0.id == id } ?? users.first { $0.id == id }
    }

    /// 예외 실패 경로. status 가 아니라 **throw 로 온** 실패(PGRST202·5xx·오프라인)와 모르는 응답 모양을 접는다.
    private func noteWatchFailure(_ error: (any Error)?) {
        if let error, isSchemaMissing(error) {
            // 서버에 reversi_watch 가 아직 없다. 관전 입구를 잠그는 신호는 **조건 없이** 세운다(게이트와 신호는 짝).
            // 순위 깃발(`rankingUnavailable`)은 건드리지 않는다 — 서로 다른 사실이다.
            stopWatching()
            setNotice(ReversiNoticeText.unavailable)
            if !watchUnavailable { watchUnavailable = true }
            return
        }
        Self.logger.notice("watch request failed")
        let runtime = watchRuntime
        runtime.watchFailureStreak += 1
        guard runtime.watchFailureStreak >= Self.watchFailureLimit else { return }
        stopWatching()
        setNotice(ReversiNoticeText.checkConnection)
    }

    // MARK: 폴링 훅 — `pollTick(at:)` · `windowDidShow()` 가 부른다

    /// 안전망 한 걸음: 관전 중이면 2초마다 판, 아니면 로비에서 60초마다 순위. 관전 중엔 순위를 돌리지 않는다.
    package func pollSpectatorFeatures(at now: Date) async {
        guard phase == .lobby, isWindowVisible, !isWindowOccluded, host?.session != nil else { return }
        if spectating != nil {
            if shouldPollWatch,
               now.timeIntervalSince(watchRuntime.lastWatchRequestAt) >= Self.watchPollSeconds {
                await refreshWatch()
            }
            return
        }
        guard now.timeIntervalSince(watchRuntime.lastRankingRequestAt) >= Self.rankingPollSeconds else { return }
        // ★ 관전 잠금을 이 주기에 한 번 풀어 준다(`startWatching` 이 문 앞에서 막아 자기가 자기를 못 연다).
        if watchUnavailable { watchUnavailable = false }
        if canPollRanking {
            await refreshRanking()
        } else {
            watchRuntime.lastRankingRequestAt = now
        }
    }

    /// 창이 다시 보였다: 관전 중이면 즉시 한 번, 로비면 순위 한 번 — 둘 다 1초 dedupe.
    package func spectatorWindowDidShow(at now: Date) {
        guard phase == .lobby, isWindowVisible, !isWindowOccluded, host?.session != nil else { return }
        if spectating != nil {
            if shouldPollWatch,
               now.timeIntervalSince(watchRuntime.lastWatchRequestAt) >= Self.reloadDedupeSeconds {
                Task { [weak self] in await self?.refreshWatch() }
            }
            return
        }
        if canPollRanking,
           now.timeIntervalSince(watchRuntime.lastRankingRequestAt) >= Self.reloadDedupeSeconds {
            Task { [weak self] in await self?.refreshRanking() }
        }
    }

    // MARK: 순수 매퍼

    /// 응답 → 다음 관전 상태(순수). 사람·시각은 호출부가 스토어 경계(playerUser·deviceDate)로 만들어 넘긴다.
    /// nil = 이 판 응답이 아니다. `needsFull` = 수 번호에 구멍이 있어 처음부터 다시 받아야 한다(그때 `state` 는 이전 값).
    package nonisolated static func spectateState(
        applying payload: ReversiStatePayload, to previous: ReversiSpectating, requestedSince: Int,
        black: ReversiUser?, white: ReversiUser?, turnStartedAt: Date?, deadline: Date?, startedAt: Date?
    ) -> (state: ReversiSpectating, needsFull: Bool)? {
        guard let row = payload.match, row.id?.lowercased() == previous.id else { return nil }
        let status = row.matchStatus
        guard status == .active || status == .finished else { return nil }
        let isFinished = status == .finished
        let records = (payload.moves ?? []).filter { $0.seq >= 1 }.sorted { $0.seq < $1.seq }
        let rebuild = requestedSince == 0 || records.first?.seq == 1

        var merged = rebuild ? [] : previous.plies
        var applied = rebuild ? 0 : previous.appliedSeq
        for record in records where record.seq > applied {
            if record.seq != applied + 1, !rebuild { return (previous, true) }
            merged.append(record)
            applied = record.seq
        }
        let moveCount = row.moveCount ?? applied
        if moveCount != applied, !rebuild { return (previous, true) }

        var next = previous
        next.blackUser = black
        next.whiteUser = white
        if let stake = row.stake { next.stake = stake }
        next.board = row.board ?? previous.board
        next.moveCount = moveCount
        next.appliedSeq = moveCount
        next.plies = merged
        next.lastStoneIdx = merged.last(where: { $0.kind == .stone })?.idx
        next.autoStones = Set(merged.compactMap { $0.kind == .stone && $0.auto ? $0.idx : nil })
        next.turn = isFinished ? nil : row.turn
        next.turnStartedAt = isFinished ? nil : turnStartedAt
        next.deadline = isFinished ? nil : deadline
        next.counts = row.discs ?? next.board.counts
        let result = isFinished ? row.result : nil
        next.result = result
        next.score = {
            guard let score = row.score, let b = score.black, let w = score.white, let result else { return nil }
            return ReversiScore(black: b, white: w, result: result)
        }()
        next.endReason = isFinished ? row.endReason : nil
        next.winner = result?.winner
        next.blackAutoStreak = payload.blackAutoStreak ?? previous.blackAutoStreak
        next.whiteAutoStreak = payload.whiteAutoStreak ?? previous.whiteAutoStreak
        next.startedAt = startedAt
        next.isFinished = isFinished
        next.watchers = max(0, payload.watchers ?? 0)
        return (next, false)
    }
}
