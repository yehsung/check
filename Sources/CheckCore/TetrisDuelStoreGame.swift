import Foundation

// 테트리스 대결 스토어의 **판 갈래** — 판 구동기 수명 · 판 루프(D10) · 입력 문 · 보고 루프(§4.1) · 순위.
// 저장 프로퍼티는 본문(TetrisDuelStore.swift)에 있고 여기는 로직만 둔다.
//
// ── 보고 루프 한눈에 ──
//   판 루프(창과 무관, 0.05초) ─┐
//   뷰 프레임 루프(창이 보일 때) ─┼→ tick(now:) → duel.advance → 상대 공격 차분 반영 → 숫자·흐름 → considerReport
//   입력 문(하드드롭)       ─────┘                                                        │
//                         reportReason: 준비 · 탑아웃 · 공격 증가(0.25초 바닥) · 1초 하트비트  │
//                         한 번에 하나(reportInFlight) — 응답이 오면 곧바로 한 번 더 묻는다 ←──┘
//                         3초 넘게 답이 없으면 그 보고를 버리고 새로 낸다(reportStallSeconds · reportTicket)
//   응답(ok/stale) → applyState: 시작 시각(단조 시계로) · 서버 seq 따라잡기 · 상대 판 · 상대 공격 누계 · 정산
//
// ★ 보고 값은 전부 **누계**다(지운 줄 · 보낸 공격 · 받아들인 공격). 그래서 보고 하나가 사라져도(오프라인 · 멎어서 버림)
//   다음 보고가 같은 사실을 다시 싣고, 서버 seq 가 늦게 온 옛 보고를 `stale` 로 버린다 — 재전송 큐가 필요 없다.
// ★ 앱을 다시 열면 판은 서버가 들고 있는 내 마지막 보고에서 다시 선다(`prepareDuel` · `resumePoint`) — 빈 판이 아니다.

extension TetrisDuelStore {
    // MARK: - 판 구동기 수명

    /// 진행 중 판의 구동기를 준비한다(같은 판이면 그대로 둔다). 시드가 없으면 만들지 않는다 — 서버 계약상 진행 중 판에는
    /// 언제나 있지만, 없으면 지어낸 시드로 두 사람의 조각 순서가 갈리는 것보다 판을 못 여는 편이 낫다.
    ///
    /// 이 프로세스가 이 판을 처음 보는데 서버가 **판 중에 받은 내 보고**를 이미 들고 있으면(앱을 다시 열었다 · 다시 로그인했다)
    /// 그 보고에서 판을 다시 세운다(`resumePoint` — 리뷰 RV1). 빈 판에서 다시 시작하면 침묵 판정(15초) 안에 앱을 껐다 켜는 것만으로
    /// 거의 찬 판이 비워지고, 받아들인 누계를 0 으로 두면 상대의 공격 이력이 통째로 한 번 더 들어온다.
    func prepareDuel(matchID: String, seed: Int?, me: TetrisPlayerRow?, startAtMs: Double?) {
        guard duel == nil || duelMatchID != matchID else { return }
        discardDuel()
        guard let seed else {
            Self.logger.notice("duel not prepared — active match without seed")
            return
        }
        if let point = Self.resumePoint(me: me, startAtMs: startAtMs),
           let resumed = TetrisDuelSession(seed: seed, resumingFrom: point) {
            Self.logger.notice("duel resumed from server row seq=\(point.seq) applied=\(point.garbageApplied)")
            duel = resumed
        } else {
            // 판 시작 전(준비 · 카운트다운)이거나 판 중 보고가 없다 — 새 판. 받아들인 누계는 그래도 서버 값에서 잇는다.
            duel = TetrisDuelSession(seed: seed, startingSeq: me?.seq ?? 0, garbageApplied: me?.garbageApplied ?? 0)
        }
        duelMatchID = matchID
    }

    /// 서버의 내 행이 **판이 시작된 뒤에** 받아 적은 보고면 그 보고를 재개 출발점으로(순수). 아니면 nil(새 판으로 연다).
    /// 시작 전 보고(준비 · 카운트다운 하트비트)는 빈 판이고 엔진도 아직 안 열렸으므로 이어 받을 것이 없다.
    package nonisolated static func resumePoint(me: TetrisPlayerRow?, startAtMs: Double?) -> TetrisDuelResumePoint? {
        guard let me, let seq = me.seq, seq > 0, let board = me.board, TetrisDuelBoard.isValid(board),
              let startAtMs, let lastSeenMs = me.lastSeenMs, startAtMs.isFinite, lastSeenMs.isFinite,
              lastSeenMs > startAtMs
        else { return nil }
        return TetrisDuelResumePoint(seq: seq, board: board, lines: me.lines ?? 0, garbageSent: me.garbageSent ?? 0,
                                     garbageApplied: me.garbageApplied ?? 0, pending: me.pending ?? 0,
                                     elapsedSeconds: (lastSeenMs - startAtMs) / 1000)
    }

    /// 구동기를 버린다(판 루프를 멈추고, 나가 있는 보고의 응답은 세대로 버려진다 — 요청 자체는 끊지 않는다).
    func discardDuel() {
        stopGameLoop()
        duelGeneration &+= 1
        reportInFlight = false
        reportSentAt = nil
        reportFailureStreak = 0
        duel = nil
        duelMatchID = nil
        if connectionTrouble { connectionTrouble = false }
    }

    // MARK: - 판 루프 (D10 — 창과 무관하게 흐른다)

    func startGameLoop() {
        guard gameLoopTask == nil, duel != nil else { return }
        gameLoopToken &+= 1
        let token = gameLoopToken
        gameLoopTask = Task { @MainActor [weak self] in
            while true {
                let step = self?.gameLoopStepSeconds ?? 0.05
                try? await Task.sleep(for: .seconds(step))
                guard let self, !Task.isCancelled, token == self.gameLoopToken else { return }
                guard self.duel != nil, self.match?.isFinished == false else {
                    self.gameLoopTask = nil
                    return
                }
                self.tick()
            }
        }
    }

    func stopGameLoop() {
        gameLoopToken &+= 1
        gameLoopTask?.cancel()
        gameLoopTask = nil
    }

    /// 판을 지금(단조 시계)까지 밀고, 숫자·흐름을 맞추고, 보고할 때면 보고한다.
    /// 판 루프와 뷰 프레임 루프가 함께 부른다 — 같은 시각이면 아무 일도 안 한다(따라잡기라 부르는 간격과 무관하게 같은 판이다).
    package func tick(now: TimeInterval? = nil) {
        guard duel != nil else { return }
        let instant = now ?? uptime()
        duel?.advance(to: instant)
        // 판 시작 전에 온 상대 공격은 구동기가 받지 않는다 — 시작한 뒤 첫 걸음에서 누계 차분으로 들어간다(멱등).
        duel?.absorbOpponentAttack(total: opponentAttackTotal)
        syncStats()
        refreshPhase()
        considerReport(at: instant)
    }

    /// 화면 흐름을 판 상태에서 다시 낸다(값이 같으면 쓰지 않는다 — 관찰자를 헛되게 깨우지 않게).
    func refreshPhase() {
        let next: TetrisDuelPhase
        if let match {
            if match.isFinished {
                next = .finished
            } else if let duel, duelMatchID == match.id, duel.startAt != nil {
                next = duel.started ? .playing : .countdown
            } else {
                next = .ready
            }
        } else {
            next = .lobby
        }
        if phase != next { phase = next }
    }

    /// 관찰 가능한 숫자를 구동기에서 다시 낸다(조각이 굳을 때만 실제로 바뀐다).
    func syncStats() {
        let next = duel.map {
            TetrisDuelMyStats(lines: $0.game.lines, attackSent: $0.game.attackSentTotal,
                              pendingGarbage: $0.game.pendingGarbageLines, levelFloor: $0.currentLevelFloor,
                              toppedOut: $0.toppedOut)
        }
        if myStats != next { myStats = next }
    }

    // MARK: - 시각 (뷰의 TimelineView 가 부르는 순수 조회)

    /// 판 경과초(단조 시계). 시작 시각을 모르면 nil, 카운트다운 중이면 음수.
    package func matchElapsedSeconds(at now: TimeInterval? = nil) -> TimeInterval? {
        duel?.matchElapsed(at: now ?? uptime())
    }

    /// 카운트다운 남은 초(시작 시각을 모르면 nil, 시작했으면 0).
    package func countdownSeconds(at now: TimeInterval? = nil) -> TimeInterval? {
        duel?.countdownRemaining(at: now ?? uptime())
    }

    /// 상대의 마지막 보고 뒤 흐른 초(서버 시각 보정). 모르면 nil.
    package func opponentSilenceSeconds(now: Date? = nil) -> TimeInterval? {
        opponentLastSeenAt.map { max(0, (now ?? clock()).timeIntervalSince($0)) }
    }

    // MARK: - 입력 문 (키 모니터·제스처가 부른다)
    //
    // 넣기 **전에** 판을 지금까지 민다 — 판 루프가 0.05초마다 돌므로 그 사이에 누른 키가 한 걸음 앞 시각의 판에
    // 들어가지 않게 한다. 살아 있지 않은 판(시작 전·탑아웃 뒤·정산 뒤)에서는 구동기가 누름을 버리고 뗌만 받는다.

    package func setLeftHeld(_ held: Bool) {
        advanceToNow()
        duel?.setLeftHeld(held)
    }

    package func setRightHeld(_ held: Bool) {
        advanceToNow()
        duel?.setRightHeld(held)
    }

    package func setSoftDropHeld(_ held: Bool) {
        advanceToNow()
        duel?.setSoftDropHeld(held)
    }

    package func rotate(clockwise: Bool) {
        advanceToNow()
        duel?.rotate(clockwise: clockwise)
    }

    /// 가로·세로 **한 칸**(폰 제스처·보이스오버). 굳힘이 없으므로 보고를 재촉하지 않는다 — 다음 하트비트(1초)나
    /// 하드드롭이 싣는다. 보고 값은 전부 누계라 한 칸 이동이 따로 실릴 필요가 없다.
    package func moveLeftOneCell() {
        advanceToNow()
        duel?.moveLeftOneCell()
    }

    package func moveRightOneCell() {
        advanceToNow()
        duel?.moveRightOneCell()
    }

    @discardableResult
    package func softDropOneCell() -> Bool {
        advanceToNow()
        return duel?.softDropOneCell() ?? false
    }

    package func hold() {
        advanceToNow()
        duel?.hold()
    }

    /// 하드드롭 — 굳힘이 곧 줄 지우기·공격이므로 보고를 곧바로 묻는다(최소 간격 0.25초는 구동기가 지킨다).
    package func hardDrop() {
        advanceToNow()
        duel?.hardDrop()
        syncStats()
        considerReport(at: uptime())
    }

    /// 눌린 키를 전부 놓는다(창 숨김·가림·닫힘 · 키 모니터가 포커스를 잃었을 때).
    package func releaseAllKeys() {
        duel?.releaseAllKeys()
    }

    private func advanceToNow() {
        guard duel != nil else { return }
        duel?.advance(to: uptime())
    }

    // MARK: - 보고 루프

    /// 보고할 때면 한 벌을 만들어 보낸다. 한 번에 하나만 나간다(응답이 오면 곧바로 다시 묻는다).
    /// 나가 있는 보고가 `reportStallSeconds` 넘게 답이 없으면 버리고 새로 낸다(리뷰 RV2 — 멎은 요청 하나가 하트비트를
    /// 15초 막으면 서버가 연결 끊김 패로 닫는다).
    func considerReport(at now: TimeInterval) {
        if reportInFlight, let sentAt = reportSentAt, now - sentAt >= Self.reportStallSeconds {
            abandonStalledReport(sentAt: sentAt, now: now)
        }
        guard !reportInFlight, let current = match, !current.isFinished,
              let duel, duelMatchID == current.id, host?.session != nil else { return }
        // 준비(첫 보고)는 창이 화면에 떠 있을 때만(머리말 ⑨). 서버가 이미 준비를 받았으면(앱을 다시 열었다) 묻지 않는다.
        if duel.lastReportAt == nil, !current.meReady, !isWindowVisible { return }
        guard let reason = duel.reportReason(at: now) else { return }
        var next = duel
        let report = next.makeReport(at: now)
        self.duel = next
        sendReport(report, reason: reason, matchID: current.id, at: now)
    }

    /// 멎은 보고를 놓는다. 요청은 끊지 않는다(세션 재시도·토큰 갱신 경로를 취소로 건드리지 않게) — 그 답은 표가 바뀌어 버려지고,
    /// 서버에 늦게 닿아도 seq 가 더 큰 다음 보고 앞에서 stale 이다. 실패 한 번으로 세어 두 번 연달아면 "연결 확인 중" 이 뜬다.
    private func abandonStalledReport(sentAt: TimeInterval, now: TimeInterval) {
        reportTicket &+= 1
        reportInFlight = false
        reportSentAt = nil
        reportFailureStreak += 1
        if reportFailureStreak >= Self.reportFailureLimit, !connectionTrouble { connectionTrouble = true }
        Self.logger.notice("report stalled \(now - sentAt, format: .fixed(precision: 1))s — abandoned streak=\(self.reportFailureStreak)")
    }

    private func sendReport(_ report: TetrisDuelReport, reason: TetrisDuelReportReason, matchID: String,
                            at now: TimeInterval) {
        reportInFlight = true
        reportSentAt = now
        reportTicket &+= 1
        let ticket = reportTicket
        let token = duelGeneration
        if reason != .heartbeat {
            Self.logger.notice("report reason=\(String(describing: reason), privacy: .public) seq=\(report.seq)")
        }
        reportTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await self.perform({
                try await $0.tetrisReport(accessToken: $1, matchID: matchID, report: report)
            })
            let receivedAt = self.uptime()
            // 판이 바뀌었다(접기 · 로그아웃 · 다른 판) — 이 응답은 지금 판의 것이 아니다.
            guard token == self.duelGeneration else { return }
            // 멎어서 버린 보고의 늦은 답이다 — 그 뒤에 낸 보고가 자리를 쥐고 있다(그 답이 같은 사실을 더 새로 싣는다).
            guard ticket == self.reportTicket else { return }
            self.reportInFlight = false
            self.reportSentAt = nil
            guard let result else { return }
            self.applyReportResult(result, matchID: matchID, receivedAt: receivedAt)
            // 왕복 사이에 공격이 늘었거나 탑아웃했다 — 다음 판 루프 걸음을 기다리지 않는다.
            self.considerReport(at: self.uptime())
        }
    }

    /// 보고 응답 하나를 옮긴다. `ok`·`stale` 둘 다 상태를 싣는다 — stale 은 "쓰지 않았다" 일 뿐 상태는 사실이다.
    func applyReportResult(_ result: Result<TetrisActionResponse, any Error>, matchID: String,
                           receivedAt: TimeInterval) {
        switch result {
        case .failure(let error):
            reportFailureStreak += 1
            if reportFailureStreak >= Self.reportFailureLimit, !connectionTrouble { connectionTrouble = true }
            if isSchemaMissing(error) { noteServerMissing() }
            Self.logger.notice("report failed streak=\(self.reportFailureStreak)")
        case .success(let response):
            reportFailureStreak = 0
            if connectionTrouble { connectionTrouble = false }
            noteServerNow(response.serverNowMs)
            switch response.status {
            case .ok, .stale:
                if let state = response.state { applyState(state, receivedAt: receivedAt) }
            case .notFound:
                // 판이 사라졌다(계정 삭제의 cascade 등) — 그 판을 내린다.
                if match?.id == matchID {
                    clearMatch()
                    setNotice(TetrisDuelNoticeText.finishedMatch)
                }
            case .unsupportedClient:
                noteUpdateRequired()
            case .notSignedIn:
                setNotice(TetrisDuelNoticeText.signInAgain)
            default:
                Self.logger.notice("report refused status=\(response.status.rawValue, privacy: .public)")
            }
        }
    }

    // MARK: - 순위

    /// 순위표 한 번. 도는 중이면 **합치지 않고 버린다**(60초 주기 목록이라 뒤따르는 한 번이 필요 없다).
    /// 실패는 안내줄로 새지 않는다 — 판 상태줄을 가린다. 깃발만 세우고 들고 있던 목록은 지우지 않는다.
    package func loadRanking() async {
        guard rankingEnabled, host?.session != nil, !rankingInFlight else { return }
        rankingInFlight = true
        let generation = resetGeneration
        defer { if generation == resetGeneration { rankingInFlight = false } }
        lastRankingRequestAt = clock()
        guard let result = await perform({ try await $0.tetrisRanking(accessToken: $1) }) else { return }
        switch result {
        case .success(let response):
            applyRanking(response)
        case .failure(let error):
            if isSchemaMissing(error) {
                if !rankingUnavailable { rankingUnavailable = true }
                if rankingLoadFailed { rankingLoadFailed = false }
                if !hasLoadedRanking { hasLoadedRanking = true }
            } else if !rankingLoadFailed {
                rankingLoadFailed = true
            }
        }
    }

    package func applyRanking(_ response: TetrisRankingResponse) {
        guard response.status == .ok else {
            Self.logger.notice("ranking refused status=\(response.status.rawValue, privacy: .public)")
            if !rankingLoadFailed { rankingLoadFailed = true }
            return
        }
        noteServerNow(response.serverNowMs)
        if rankingLoadFailed { rankingLoadFailed = false }
        if rankingUnavailable { rankingUnavailable = false }
        if !hasLoadedRanking { hasLoadedRanking = true }
        let board = Self.rankingBoard(from: response)
        if ranking != board { ranking = board }
    }

    /// 순위 탭을 열었다 등(60초 스로틀).
    package func refreshRankingIfStale() {
        guard rankingEnabled, host?.session != nil else { return }
        guard clock().timeIntervalSince(lastRankingRequestAt) >= Self.rankingPollSeconds else { return }
        Task { [weak self] in await self?.loadRanking() }
    }

    /// 내 판이 끝났다 — 전적이 바뀐 순간 순위도 다시 읽는다(창이 안 보여도 사건에 대한 한 번).
    func noteOwnMatchFinishedForRanking() {
        lastRankingRequestAt = .distantPast
        guard rankingEnabled, host?.session != nil else { return }
        Task { [weak self] in await self?.loadRanking() }
    }

    /// 응답 → 순위표(순수). **행 순서는 입력 그대로**. id 나 rank 가 빠진 행은 싣지 않는다.
    package nonisolated static func rankingBoard(from response: TetrisRankingResponse) -> TetrisDuelRankingBoard {
        let entries = (response.rows ?? []).compactMap { row -> TetrisDuelRankEntry? in
            guard let rank = row.rank,
                  let user = user(from: TetrisUserRow(id: row.id, displayName: row.displayName,
                                                      avatarUrl: row.avatarUrl, character: row.character))
            else { return nil }
            let wins = row.wins ?? 0
            let losses = row.losses ?? 0
            return TetrisDuelRankEntry(id: user.id, rank: rank, user: user, wins: wins, losses: losses,
                                       draws: row.draws ?? 0, points: row.points ?? (wins - losses))
        }
        let mine = response.me.map { me -> TetrisDuelMyRank in
            let wins = me.wins ?? 0
            let losses = me.losses ?? 0
            return TetrisDuelMyRank(rank: me.rank, wins: wins, losses: losses, draws: me.draws ?? 0,
                                    points: me.points ?? (wins - losses))
        }
        let since = response.recordSinceMs.flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0 / 1000) : nil }
        return TetrisDuelRankingBoard(entries: entries, me: mine, recordSince: since)
    }
}
