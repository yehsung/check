import Foundation

// 1:1 길건너 스토어의 **판 갈래** — 판 구동기 수명 · 판 루프 · 입력 문 · 보고 루프 · 한 판 한 기기 · 경주 스냅숏
// (SPEC v1.3 §8.3 · §3.1 · §3.4 B4 · §8.4 스냅숏 — `TetrisDuelStoreGame` 틀). 저장 프로퍼티는 본문에 있고 여기는 로직만 둔다.
//
//   판 루프(창과 무관, 0.05초) ─┐
//   뷰 프레임 루프(창이 보일 때) ─┼→ tick(now:) → duel.advance → 흐름 → considerFrame → considerReport
//   입력 문(hop · forward)  ─────┘
//   considerReport: `CrossyDuelSession.reportDue`(준비 · goal · cap · postGrace · 변화 · 하트비트) — 간격은 장부가 정한다
//                   (프레임 확인됨 = 체크포인트 · 변화 보고 0 / 대체 길 = report_ms · heartbeat_ms).
//                   한 번에 하나(goal · cap 만 예외 — 비행 중 보고를 안 기다린다, v1.1 CC-3) · 3초 답 없으면 버리고 새로 ·
//                   두 번 연달아 실패면 `connectionTrouble` — **55P03(lock_timeout)은 실패로 세지 않는다**(CC-21).
//   응답(ok/stale) → applyState: 시작 시각 · 서버 seq · 서버 점수가 크면 다시 세움(CC-22) · 상대 점수 · 정산 · 프레임 켬/끔
//
// ★ 판정 · 루비는 **서버 값만**. 3분 얼림 · 100 도달 뒤에도 결과가 올 때까지 하트비트를 멈추지 않는다(`waitingForResult` —
//   서버 NOTES §8-2: 동시 goal 판은 다음 호출이 닫는다).
// ★ 구동기는 **이 기기가 두는 판**에서만 선다(`playsMatch`). 구동기가 없으면 판 루프 · 준비/보고 · 입력 문이 전부 서지 않는다.

extension CrossyDuelStore {
    // MARK: - 판 구동기 수명

    /// 진행 중 판의 구동기를 준비한다(같은 판이면 그대로 둔다). 씨앗이 없으면 만들지 않는다(지어낸 씨앗으로 두 맵이 갈리는 것보다
    /// 판을 못 여는 편이 낫다). 서버가 **판 중에 받은 내 보고**를 이미 들고 있으면(앱을 다시 열었다) 그 값에서 이어 선다(`resume`).
    func prepareDuel(matchID: String, payload: CrossyDuelStatePayload) {
        guard duel == nil || duelMatchID != matchID else { return }
        discardDuel()
        guard let seed = payload.seed else {
            Self.logger.notice("duel not prepared — active match without seed")
            return
        }
        var session = CrossyDuelSession(
            seed: seed, goal: payload.goal ?? CrossyDuelSession.expectedGoal,
            maxDurationSeconds: payload.maxDurationSeconds ?? CrossyDuelSession.expectedMaxDurationSeconds,
            startingSeq: payload.me?.seq ?? 0)
        if let point = Self.resumePoint(me: payload.me, startAtMs: payload.startAtMs) {
            session.resume(score: point.score, deaths: point.deaths, seq: point.seq)
            Self.logger.notice("duel resumed from server row seq=\(point.seq) score=\(point.score)")
        }
        duel = session
        duelMatchID = matchID
    }

    /// 서버의 내 행이 **판이 시작된 뒤에** 받아 적은 보고면 재개 출발점(순수). 아니면 nil(새 판으로 연다 — 시작 전 보고는 빈 판이다).
    package nonisolated static func resumePoint(me: CrossyDuelSideRow?, startAtMs: Double?)
        -> (score: Int, deaths: Int, seq: Int)? {
        guard let me, let seq = me.seq, seq > 0, me.ready == true,
              let startAtMs, let lastSeenMs = me.lastSeenMs, startAtMs.isFinite, lastSeenMs.isFinite,
              lastSeenMs > startAtMs
        else { return nil }
        return (max(0, me.score ?? 0), max(0, me.deaths ?? 0), seq)
    }

    /// 구동기를 버린다(판 루프 · 프레임 소켓까지 — 나가 있는 보고의 응답은 세대로 버려진다).
    func discardDuel() {
        stopGameLoop()
        discardFrames()
        duelGeneration &+= 1
        reportInFlight = false
        reportSentAt = nil
        reportInFlightKind = nil
        reportFailureStreak = 0
        duel = nil
        duelMatchID = nil
        if connectionTrouble { connectionTrouble = false }
    }

    // MARK: - 판 루프 (창과 무관하게 흐른다)

    func startGameLoop() {
        guard gameLoopTask == nil, duel != nil else { return }
        gameLoopToken &+= 1
        let token = gameLoopToken
        gameLoopTask = Task { @MainActor [weak self] in
            while true {
                let step = self?.gameLoopStepSeconds ?? CrossyDuelStore.gameLoopSeconds
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

    /// 판 루프 한 걸음 + 보고 판단(창과 무관 — 테트리스 D10). 인자가 없으면 `uptime()`(v1.1 CC-1 — 벽시계를 읽지 않는다).
    /// 같은 시각이면 아무 일도 안 한다(따라잡기라 부르는 간격과 무관하게 같은 판이다).
    package func tick(now: TimeInterval? = nil) {
        guard duel != nil else { return }
        let instant = now ?? uptime()
        duel?.advance(to: instant)
        refreshPhase()
        // 프레임은 보고보다 **먼저**, 따로 묻는다 — 나가 있는 보고가 프레임을 막지 않는다.
        considerFrame(at: instant)
        considerReport(at: instant)
    }

    /// 화면 흐름을 판 상태에서 다시 내고, 끝에서 활동 붙들기 신호를 맞춘다(v1.1 CC-10 — countdown 진입은 소유 변경이 아니다).
    func refreshPhase() {
        let next: CrossyDuelPhase
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
        syncHoldingActivity()
    }

    /// `holdsActivity` 가 바뀌었으면 한 번 알린다.
    func syncHoldingActivity() {
        let holding = holdsActivity
        guard holding != lastHoldingActivity else { return }
        lastHoldingActivity = holding
        onHoldingActivityChange?(holding)
    }

    // MARK: - 입력 문

    /// 방향 입력(판 중에만 — 얼었거나 시작 전이면 구동기가 무시한다). 넣기 **전에** 판을 지금까지 민다.
    package func hop(_ direction: CrossyGame.Direction) {
        guard phase == .playing, !playingElsewhere, duel != nil else { return }
        duel?.advance(to: uptime())
        duel?.input(direction)
    }

    /// 앞으로 한 칸(스페이스·클릭).
    package func forward() {
        hop(.forward)
    }

    // MARK: - 경주 스냅숏

    /// 경주 트랙 값 하나(v1.1 단조 시계, CC-1). 판이 없으면 nil.
    ///  · 내 점수 = 로컬 엔진(끝난 판은 `finishedMyScore` — Q3 (가): goal 로 진 판만 `max(final.me, 로컬)`, 그 밖은 `final.me`)
    ///  · 상대 점수 = 끝나지 않은 판에서 `max(프레임 sc, DB opponent.score)`(B3), 끝난 판은 `final.opponent`
    ///  · `opponentQuiet` = 상대의 마지막 증거(DB last_seen — 서버 시각끼리 · 프레임 수신 — 단조) 뒤 8초 넘음(CC-19 · §8.4)
    ///  · `waitingForResult` = 내 판이 얼었거나(3분) 100 에 닿았는데 서버 결과가 아직 없다
    package func raceSnapshot(at now: TimeInterval? = nil) -> CrossyDuelRaceSnapshot? {
        guard let match else { return nil }
        let t = now ?? uptime()
        let ownDuel = duelMatchID == nil || duelMatchID == match.id ? duel : nil
        let game = ownDuel?.game
        let goal = game?.rules.goalScore ?? CrossyDuelSession.expectedGoal
        let localScore = game?.score ?? match.myServerScore
        let myScore = match.isFinished ? Self.finishedMyScore(match: match, localScore: game?.score) : localScore
        let link = frameLinkMatchID == nil || frameLinkMatchID == match.id ? frameLink : nil
        let opponentScore = match.isFinished ? (match.finalOpponentScore ?? match.opponentScore)
                                             : (link?.mergedOpponentScore(db: match.opponentScore) ?? match.opponentScore)
        var respawnIn: TimeInterval?
        if let game, !match.isFinished, game.rules.respawnDelay != nil, case .over(let hold) = game.phase {
            respawnIn = max(0, hold)
        }
        let shielded = game.map { g in g.respawnShield.map { g.elapsed < $0.until } ?? false } ?? false
        let countdown = match.isFinished ? nil : ownDuel?.countdownRemaining(at: t).flatMap { $0 > 0 ? $0 : nil }
        let reachedGoal = (game?.score ?? 0) >= goal
        let frozen = match.isFinished || (ownDuel?.finished ?? false) || reachedGoal
        let waiting = !match.isFinished && ((ownDuel?.finished ?? false) || reachedGoal)
        return CrossyDuelRaceSnapshot(
            myScore: myScore, opponentScore: opponentScore, goal: goal,
            myDeaths: game?.deaths ?? 0, opponentDeaths: match.opponentDeaths,
            countdown: countdown, remaining: match.isFinished ? 0 : ownDuel?.remaining(at: t), respawnIn: respawnIn,
            shielded: shielded && !match.isFinished, frozen: frozen, waitingForResult: waiting,
            opponentQuiet: !match.isFinished && opponentQuiet(at: t))
    }

    /// 끝난 판의 '나' 숫자(SPEC §3.1 · §9.3 Q3 (가) "진 판은 내가 본 점수") — goal 로 **진** 판만 `max(final.me, 로컬)`, 그 밖은
    /// `final.me`(없으면 로컬 · 서버 값 순). 결과 카드와 트랙이 이 함수 하나를 읽는다(CC-4). 기록·순위는 서버 값 그대로다.
    package nonisolated static func finishedMyScore(match: CrossyDuelMatchState, localScore: Int?) -> Int {
        let settled = match.finalMyScore ?? localScore ?? match.myServerScore
        guard match.endReason == .goal, match.outcome == .loss, let localScore else { return settled }
        return max(settled, localScore)
    }

    /// 상대가 조용한가(8초). 재료 둘 중 **최근 증거**를 쓴다 — DB(`server_now − last_seen` + 받은 뒤 흐른 단조 시간)와
    /// 프레임 수신(단조). 둘 다 없으면 거짓(모르는 것을 조용하다고 하지 않는다).
    package func opponentQuiet(at now: TimeInterval) -> Bool {
        var silence: TimeInterval?
        if let atReceipt = opponentSilenceAtReceipt, let received = opponentSilenceReceivedAt {
            silence = atReceipt + max(0, now - received)
        }
        if let heard = frameLink?.opponentHeardAt, frameLinkMatchID == match?.id {
            let framed = max(0, now - heard)
            silence = silence.map { min($0, framed) } ?? framed
        }
        guard let silence else { return false }
        return silence > Self.opponentQuietSeconds
    }

    // MARK: - 보고 루프

    /// 보고할 때면 한 벌을 만들어 보낸다. 나가 있는 보고가 3초 넘게 답이 없으면 버리고 새로 낸다.
    func considerReport(at now: TimeInterval) {
        if reportInFlight, let sentAt = reportSentAt, now - sentAt >= CrossyDuelSession.reportStallSeconds {
            abandonStalledReport(sentAt: sentAt, now: now)
        }
        guard let current = match, !current.isFinished, let duel, duelMatchID == current.id,
              host?.session != nil else { return }
        // 준비(첫 보고)는 창이 보일 때만 — 가려진 창도 보낸다(§3.1 · 테트리스 준비 문 "두기"). 서버가 이미 준비를 받았으면 문이 열려 있다.
        let windowOpen = isWindowVisible || current.meReady
        let confirmed = frameChangeReportsSuppressed(at: now)
        let heartbeat = confirmed ? (frameLink?.checkpointMs ?? current.heartbeatMs) : current.heartbeatMs
        guard let kind = duel.reportDue(now: now, reportMs: current.reportMs, heartbeatMs: heartbeat,
                                        windowVisible: windowOpen, changeReportsSuppressed: confirmed)
        else { return }
        var next = duel
        let body = next.makeReport(kind, at: now)
        self.duel = next
        sendReport(body, kind: kind, matchID: current.id, at: now)
    }

    /// 멎은 보고를 놓는다(요청은 끊지 않는다 — 그 답은 표가 바뀌어 버려진다). 실패 한 번으로 센다.
    /// 결승 보고(goal · cap · postGrace)였으면 다음 걸음에 같은 종류로 다시 낸다.
    private func abandonStalledReport(sentAt: TimeInterval, now: TimeInterval) {
        reportTicket &+= 1
        reportInFlight = false
        reportSentAt = nil
        duel?.reportSettled()
        if let kind = reportInFlightKind, kind == .goal || kind == .cap || kind == .postGrace { duel?.reportNeedsRetry(kind) }
        reportInFlightKind = nil
        reportFailureStreak += 1
        noteFrameReportStreak()
        if reportFailureStreak >= Self.reportFailureLimit, !connectionTrouble { connectionTrouble = true }
        Self.logger.notice("report stalled \(now - sentAt, format: .fixed(precision: 1))s — abandoned streak=\(self.reportFailureStreak)")
    }

    private func sendReport(_ report: CrossyDuelReportBody, kind: CrossyDuelSession.ReportKind, matchID: String,
                            at now: TimeInterval) {
        reportInFlight = true
        reportSentAt = now
        reportInFlightKind = kind
        reportTicket &+= 1
        let ticket = reportTicket
        let token = duelGeneration
        if kind != .heartbeat {
            Self.logger.notice("report kind=\(String(describing: kind), privacy: .public) seq=\(report.seq) score=\(report.score)")
        }
        reportTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await self.perform({
                try await $0.crossyDuelReport(accessToken: $1, matchID: matchID, report: report)
            })
            let receivedAt = self.uptime()
            guard token == self.duelGeneration else { return }
            // 버렸거나 goal·cap 이 앞지른 보고의 늦은 답 — 그 뒤에 낸 보고가 자리를 쥐고 있다(같은 사실을 더 새로 싣는다).
            guard ticket == self.reportTicket else { return }
            self.reportInFlight = false
            self.reportSentAt = nil
            self.reportInFlightKind = nil
            self.duel?.reportSettled()
            guard let result else { return }
            self.applyReportResult(result, matchID: matchID, receivedAt: receivedAt, kind: kind)
            self.considerReport(at: self.uptime())
        }
    }

    /// 보고 응답 하나를 옮긴다. `ok`·`stale` 둘 다 상태를 싣는다 — stale 은 "쓰지 않았다" 일 뿐 상태는 사실이다.
    /// - Parameter kind: 이 응답의 보고 종류. 실패면 55P03 은 무엇이든 · 그 밖의 실패는 결승 보고(goal · cap · postGrace)만
    ///   다음 걸음에 다시 낸다(나머지는 다음 간격이 누계를 다시 싣는다).
    func applyReportResult(_ result: Result<CrossyDuelActionResponse, any Error>, matchID: String,
                           receivedAt: TimeInterval, kind: CrossyDuelSession.ReportKind? = nil) {
        switch result {
        case .failure(let error):
            if error is CrossyDuelLockNotAvailable {
                // 55P03 — 정산 경합의 순간이 바로 결승선이다. 실패로 세지 않고 다음 걸음에 다시 보낸다(CC-21).
                Self.logger.notice("report lock timeout — retry next step")
                if let kind { duel?.reportNeedsRetry(kind) }
                return
            }
            if let kind, kind == .goal || kind == .cap || kind == .postGrace { duel?.reportNeedsRetry(kind) }
            reportFailureStreak += 1
            noteFrameReportStreak()
            if reportFailureStreak >= Self.reportFailureLimit, !connectionTrouble { connectionTrouble = true }
            if isSchemaMissing(error) { noteServerMissing() }
            Self.logger.notice("report failed streak=\(self.reportFailureStreak)")
        case .success(let response):
            reportFailureStreak = 0
            noteFrameReportStreak()
            if connectionTrouble { connectionTrouble = false }
            noteServerNow(response.serverNowMs)
            switch response.status {
            case .ok, .stale:
                if let state = response.state { applyState(state, receivedAt: receivedAt) }
            case .otherDevice:
                Self.logger.notice("report refused — another device plays this match")
                yieldMatchToOtherDevice(matchID)
                if let state = response.state { applyState(state, receivedAt: receivedAt) }
            case .notFound:
                if match?.id == matchID {
                    clearMatch()
                    setNotice(CrossyDuelNoticeText.finishedMatch)
                }
            case .unsupportedClient:
                noteUpdateRequired()
            case .notSignedIn:
                setNotice(CrossyDuelNoticeText.signInAgain)
            default:
                Self.logger.notice("report refused status=\(response.status.rawValue, privacy: .public)")
            }
        }
    }

    // MARK: - 한 판 한 기기 (서버 `my_device` → 없으면 장부)

    /// 이 기기가 이 판을 **두는가**. 물러난 판이면 아니다 · 서버가 'this' 면 둔다 · 'other' 면 안 둔다 · 말이 없으면 장부.
    package func playsMatch(_ matchID: String, serverSays myDevice: String?) -> Bool {
        let id = matchID.lowercased()
        if yieldedMatchIDs.contains(id) { return false }
        switch myDevice {
        case "this": return true
        case "other": return false
        default: return ownsMatch(id)
        }
    }

    /// 이 기기가 이 판을 열었다는 기록이 있는가(지금 로그인한 사람의 기록만).
    package func ownsMatch(_ matchID: String) -> Bool {
        deviceLedger.owns(matchID, userID: host?.session?.userID, now: clock())
    }

    /// 이 기기가 이 판을 열었다(신청 ok · 수락 ok · 서버가 'this' 라 했다).
    func noteOwnsMatch(_ matchID: String) {
        deviceLedger.note(matchID, userID: host?.session?.userID, now: clock())
    }

    /// 이 판의 기록을 지운다(끝났다 · 거절·만료 · 서버가 'other' 라 했다 · 물러났다).
    func dropOwnership(_ matchID: String) {
        deviceLedger.drop(matchID, userID: host?.session?.userID, now: clock())
    }

    /// 서버가 이 판의 보고·기권을 다른 기기의 것으로 돌려보냈다(`other_device`). 판 루프를 **곧바로** 멈추고 구동기를 버리고
    /// 기록을 지우고, 같은 판은 다시 두지 않는다. 판 상태는 남겨 화면이 안내 한 줄을 그린다.
    func yieldMatchToOtherDevice(_ matchID: String) {
        let id = matchID.lowercased()
        yieldedMatchIDs.insert(id)
        dropOwnership(id)
        if duelMatchID == id || match?.id == id { discardDuel() }
        if let current = match, current.id == id, !current.isFinished {
            if !playingElsewhere { playingElsewhere = true }
            setNotice(CrossyDuelNoticeText.otherDevice)
        }
        refreshPhase()
    }
}
