import Foundation

// 아잉 큐브 스토어 — state 깔때기 · 편집기 재구성 · 차례 동작(끌기·되돌리기·정렬·완료·뽑기) · 작업 상태 전송 · 마감.
// 규약은 RummyStore.swift 머리말 ①~⑩.

extension RummyStore {
    // MARK: - 판 조회

    /// 한 방·판의 state 를 읽는다. 도는 중에 또 불리면 뒤따르는 한 번으로 합친다.
    /// 도는 중에 **다른 판** id 가 들어오면 기억했다가 지금 것을 끝낸 뒤 그 판을 한 번 읽는다.
    package func refreshMatch(id: UUID?) async {
        guard let id, host?.session != nil else { return }
        if stateInFlight {
            if id == stateInFlightID { stateAgain = true } else { pendingStateID = id }
            return
        }
        stateInFlight = true
        let generation = resetGeneration
        var nextID: UUID? = id
        while let current = nextID {
            nextID = nil
            stateInFlightID = current
            repeat {
                stateAgain = false
                lastStateRequestAt = clock()
                let ticket = issueTicket()
                let result = await perform({ try await $0.rummyState(accessToken: $1, matchID: current) })
                guard generation == resetGeneration else { return }
                switch result {
                case .success(let response)?:
                    noteServerNow(response.serverNowMs)
                    switch response.status {
                    case .ok:
                        if let state = response.state { applyState(state, ticket: ticket) }
                    case .notFound:
                        // 내 자리가 없는 방·판(지워졌거나 정리됐다).
                        if match?.id == current, match?.status != .finished {
                            clearMatch()
                            setNotice(RummyNoticeText.roomClosed)
                        }
                        if activeMatchID == current { activeMatchID = nil }
                    case .unsupportedClient:
                        noteUpdateRequired()
                    case .unauthorized:
                        setNotice(RummyNoticeText.signInAgain)
                    default:
                        Self.logger.notice("state refused status=\(response.status.rawValue, privacy: .public)")
                    }
                case .failure(let error)?:
                    if isSchemaMissing(error) { noteServerMissing() }
                case nil:
                    break
                }
            } while stateAgain
            if let pending = pendingStateID {
                pendingStateID = nil
                nextID = pending
            }
        }
        stateInFlightID = nil
        stateInFlight = false
    }

    package enum StateApplyOutcome: Equatable { case applied, ignored }

    /// 서버 state 를 화면 상태로 옮기는 **유일한 깔때기**(조회 · 참가 · 시작 · 완료 · 뽑기 · 거절에 실린 state 전부).
    ///
    /// 늦은 응답 가드(머리말 ④):
    ///  (a) 접은 판(`dismissedMatchIDs`)의 state 는 무시한다.
    ///  (b) 이미 끝남으로 든 판에 끝나지 않은 응답이 오면 무시한다(끝나기 전에 읽힌 옛 스냅숏).
    ///  (c) 같은 판이면 `seq` → `draft_seq` → 요청 표 순으로 대어 **더 옛것이면** 무시한다(forming 방은 seq 가 안 오른다).
    ///  (d) 다른 판이면 요청 표가 더 옛것일 때 무시한다(방을 옮긴 뒤 늦게 온 옛 방의 응답).
    /// - Parameter ticket: 그 요청을 **보낼 때** 뗀 표. nil 이면 지금 새로 뗀다(가장 새것으로 친다).
    @discardableResult
    package func applyState(_ state: RummyMatchState, ticket: Int? = nil) -> StateApplyOutcome {
        let id = state.id
        guard !dismissedMatchIDs.contains(id) else { return .ignored }
        let ticket = ticket ?? issueTicket()
        let seq = state.seq ?? 0
        let draftSeq = state.draft?.draftSeq ?? 0
        if let current = match {
            if current.id == id {
                if current.status == .finished, state.status != .finished { return .ignored }
                let heldSeq = current.seq ?? 0
                if seq < heldSeq { return .ignored }
                if seq == heldSeq {
                    let heldDraft = current.draft?.draftSeq ?? 0
                    if draftSeq < heldDraft { return .ignored }
                    if draftSeq == heldDraft, ticket < appliedTicket { return .ignored }
                }
            } else if ticket < appliedTicket {
                return .ignored
            }
        }
        noteServerNow(state.serverNowMs)

        // 닫힌 방(취소·만료) — 들고 있던 방이면 내리고 한 줄.
        if state.status == .cancelled || state.status == .expired {
            if match?.id == id {
                appliedTicket = max(appliedTicket, ticket)
                clearMatch()
                setNotice(RummyNoticeText.roomClosed)
            }
            if activeMatchID == id { activeMatchID = nil }
            return .applied
        }
        // 내 자리가 아닌 state(초대만 받은 방 · 시작 검사에서 빠진 방 · 시작 때 declined 로 접힌 자리)는 들지 않는다.
        guard isParticipant(state) else {
            if match?.id == id {
                appliedTicket = max(appliedTicket, ticket)
                let dropped = mySeat(in: state)?.state == .dropped
                clearMatch()
                setNotice(dropped ? RummyNoticeText.droppedFromRoom : RummyNoticeText.roomClosed)
            }
            return .ignored
        }

        appliedTicket = max(appliedTicket, ticket)
        let previous = match
        if previous != state { match = state }
        reconcileEditor(with: state)
        refreshPhase()
        announce(previous: previous, state: state)
        scheduleDeadlineWake()
        return .applied
    }

    /// 이 state 에서 내 자리(내 id 로, 호스트가 없으면 `my_seat_no` 로).
    func mySeat(in state: RummyMatchState) -> RummyMatchSeat? {
        Self.mySeat(in: state, me: myUserID)
    }

    package nonisolated static func mySeat(in state: RummyMatchState, me: String?) -> RummyMatchSeat? {
        if let me, let seat = state.seats?.first(where: { $0.userId.uuidString.lowercased() == me }) { return seat }
        guard let mine = state.mySeatNo else { return nil }
        return state.seats?.first { $0.seatNo == mine }
    }

    /// 내가 이 방·판의 사람인가 — 방이면 joined, 판이면 playing·forfeit·done.
    func isParticipant(_ state: RummyMatchState) -> Bool {
        guard let seat = mySeat(in: state) else {
            // 자리 줄을 못 찾았다(옛 모양·미리보기) — 서버가 내 자리 번호를 줬으면 믿는다.
            return state.mySeatNo != nil
        }
        switch state.status {
        case .forming?: return seat.state == .joined || seat.state == nil
        default:
            guard let seatState = seat.state else { return true }
            return seatState == .playing || seatState == .forfeit || seatState == .done || seatState == .unknown
        }
    }

    /// 내 차례인가(판 active · 차례 자리 = 내 자리 · 내 자리가 아직 playing).
    package nonisolated static func isMyTurn(_ state: RummyMatchState?, me: String?) -> Bool {
        guard let state, state.status == .active, let mine = state.mySeatNo, state.turnSeatNo == mine else {
            return false
        }
        let seat = mySeat(in: state, me: me)
        return seat?.state == nil || seat?.state == .playing
    }

    // MARK: - 편집기

    /// 편집기를 state 에 맞춘다(머리말 ⑩): 판이 active 이고 내가 playing 이면 seq 마다 다시 세우고(랙 배치 보존),
    /// seq 가 같으면 그대로 둔다(작업 보존). 아니면 내린다.
    func reconcileEditor(with state: RummyMatchState) {
        let seat = mySeat(in: state)
        guard state.status == .active, let rack = state.myRack,
              seat?.state == nil || seat?.state == .playing else {
            if editor != nil { editor = nil }
            editorKey = nil
            lastSentDraft = nil
            cancelDraft()
            return
        }
        let key = RummyEditorKey(matchID: state.id, seq: state.seq ?? 0)
        if editor != nil, editorKey == key { return }
        let order = editorKey?.matchID == state.id ? editor?.rackFaces : nil
        let table = state.table ?? []
        let fresh = RummyTurnEditor(
            table: table, rack: rack, initialDone: state.myInitialDone ?? false, rackOrder: order)
        editor = fresh
        editorKey = key
        cancelDraft()
        draftRetryCount = 0
        // 서버가 들고 있는 작업 판. 새 차례면 null(= 시작 판)이다.
        lastSentDraft = state.draft?.table ?? table
        // 차례 중간에 편집기를 새로 세웠는데(앱 재실행) 서버 작업 판이 내 화면과 다르면 맞춘다 — 시간 초과 때 서버는
        // 그 작업 판을 판정한다(R-19). 내 화면에 없는 판이 나 대신 내지지 않게 한다.
        // 비교는 K(다중집합) — 서버가 판정하는 기준과 같고, 편집기가 세트 안 순서를 표시 순서로 바꿔도 헛보내지 않는다.
        if Self.isMyTurn(state, me: myUserID), let serverDraft = state.draft?.table,
           !RummyRules.sameTable(serverDraft, fresh.submissionTable) {
            scheduleDraft()
        }
    }

    // MARK: - 알림(판 시작 · 내 차례 · 끝남)

    func announce(previous: RummyMatchState?, state: RummyMatchState) {
        let id = state.id
        if state.status == .finished {
            if !finishAnnouncedIDs.contains(id) {
                finishAnnouncedIDs.insert(id)
                onMatchFinished?()
            }
            return
        }
        guard state.status == .active else { return }
        let myTurn = Self.isMyTurn(state, me: myUserID)
        let turnKey = "\(id.uuidString.lowercased())#\(state.seq ?? 0)"
        let windowShown = isWindowVisible && !isWindowOccluded
        if !startAnnouncedIDs.contains(id) {
            // 판으로 **처음** 넘어갔다 — 창을 띄우고 주의를 끈다(테트리스 noteMatchStarted 와 같은 길).
            startAnnouncedIDs.insert(id)
            if myTurn { turnAnnouncedKeys.insert(turnKey) }
            presentWindow?()
            guard !windowShown else { return }
            requestAttention?()
            onAttention?(myTurn ? RummyNoticeText.myTurnAttention : RummyNoticeText.matchStartedAttention)
            return
        }
        guard myTurn, !turnAnnouncedKeys.contains(turnKey) else { return }
        turnAnnouncedKeys.insert(turnKey)
        guard !windowShown else { return }
        requestAttention?()
        onAttention?(RummyNoticeText.myTurnAttention)
    }

    // MARK: - 차례 동작

    /// 끌어 놓기. 내 차례면 작업 판을 바꾸고 작업 상태를 보낸다(디바운스). 내 차례가 아니면 **랙 안 재배치만** 받는다.
    package func moveTile(_ tileID: Int, to target: RummyDropTarget) {
        guard var working = editor else { return }
        let myTurn = isMyTurn
        if !myTurn {
            guard case .rack = target, !working.isFromTable(tileID),
                  working.rack.contains(where: { $0.id == tileID }) else { return }
        }
        guard working.move(tileID, to: target) else { return }
        if editor != working { editor = working }
        guard myTurn else { return }
        setNotice(nil)
        scheduleDraft()
    }

    /// 이번 차례 처음 상태로(랙 순서는 유지). 되돌린 판도 보낸다(남들이 보는 작업 판을 되돌린다).
    package func resetTurn() {
        guard var working = editor, isMyTurn else { return }
        working.reset()
        if editor != working { editor = working }
        setNotice(nil)
        scheduleDraft()
    }

    /// 랙 정렬(777 · 789). 차례와 무관하고 서버로 가지 않는다.
    package func sortRack(_ mode: RummyRackSort) {
        guard var working = editor else { return }
        working.sortRack(mode)
        if editor != working { editor = working }
    }

    /// [완료]. 편집기가 이미 거절을 아는 판은 보내지 않고 이유 한 줄만 낸다(서버가 같은 판정을 다시 한다).
    package func submitTurn() {
        guard let current = match, let working = editor, isMyTurn else { return }
        let reason = working.reason
        if reason != .ok, reason != .unknown {
            setNotice(RummyNoticeText.reason(reason, initialPoints: working.initialPoints))
            return
        }
        let matchID = current.id
        let seq = current.seq ?? 0
        let table = working.submissionTable
        // 확정이 작업 상태를 대신한다 — 기다리던 디바운스는 걷는다(나가 있는 것은 서버가 stale 로 버린다).
        draftDebounceTask?.cancel()
        draftDebounceTask = nil
        runAction { store in
            let ticket = store.issueTicket()
            guard let result = await store.perform({
                try await $0.rummyPlay(accessToken: $1, matchID: matchID, expectedSeq: seq, table: table)
            }) else { return }
            store.handleTurnResult(result, matchID: matchID, ticket: ticket, action: .play)
        }
    }

    /// [뽑기|넘기기]. 더미가 비었으면 서버가 패스로 바꾼다.
    package func drawTile() {
        guard let current = match, isMyTurn else { return }
        let matchID = current.id
        let seq = current.seq ?? 0
        draftDebounceTask?.cancel()
        draftDebounceTask = nil
        runAction { store in
            let ticket = store.issueTicket()
            guard let result = await store.perform({
                try await $0.rummyDraw(accessToken: $1, matchID: matchID, expectedSeq: seq)
            }) else { return }
            store.handleTurnResult(result, matchID: matchID, ticket: ticket, action: .draw)
        }
    }

    /// 완료·뽑기 응답. 거절에도 state 가 실려 오면 그대로 맞춘다(같은 seq 면 편집기는 남는다 — 고쳐서 다시 낼 수 있게).
    func handleTurnResult(
        _ result: Result<RummyActionResponse, any Error>, matchID: UUID, ticket: Int, action: RummyNoticeText.Action
    ) {
        switch result {
        case .success(let response):
            noteServerNow(response.serverNowMs)
            switch response.status {
            case .ok:
                setNotice(nil)
            case .rejected:
                let reason = response.reason ?? .unknown
                setNotice(RummyNoticeText.reason(reason, initialPoints: editor?.initialPoints)
                          ?? RummyNoticeText.tryAgain)
            default:
                noteRefusal(response, action: action)
            }
            if let state = response.state {
                applyState(state, ticket: ticket)
            } else if response.status != .ok {
                Task { [weak self] in await self?.refreshMatch(id: matchID) }
            }
        case .failure(let error):
            noteActionFailure(error)
        }
    }

    // MARK: - 작업 상태 전송(머리말 ⑨)

    /// 디바운스(250ms)를 다시 건다. 끝나면 `flushDraft()`.
    package func scheduleDraft(after delay: TimeInterval? = nil) {
        guard isMyTurn, editor != nil else { return }
        draftDebounceTask?.cancel()
        let generation = resetGeneration
        let wait = delay ?? draftDebounceSeconds
        draftDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled, let self, generation == self.resetGeneration else { return }
            self.draftDebounceTask = nil
            self.flushDraft()
        }
    }

    /// 지금 작업 판을 보낸다. 나가 있는 게 있으면 **끝난 뒤 최신 것 한 번**(합치기). 서버가 이미 든 판과 같으면 안 보낸다.
    package func flushDraft() {
        if draftInFlight {
            draftDirty = true
            return
        }
        draftDirty = false
        guard let current = match, let working = editor, let key = editorKey, key.matchID == current.id,
              Self.isMyTurn(current, me: myUserID) else { return }
        let table = working.submissionTable
        guard table != lastSentDraft else { return }
        draftInFlight = true
        lastSentDraft = table
        let matchID = current.id
        let seq = key.seq
        let generation = resetGeneration
        draftFlushTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let ticket = self.issueTicket()
            let result = await self.perform({
                try await $0.rummyDraft(accessToken: $1, matchID: matchID, expectedSeq: seq, table: table)
            })
            guard generation == self.resetGeneration else { return }
            self.draftInFlight = false
            let sameTurn = self.editorKey == key
            var retry = false
            switch result {
            case .success(let response)?:
                self.noteServerNow(response.serverNowMs)
                switch response.status {
                case .ok:
                    self.draftRetryCount = 0
                case .stale, .notYourTurn, .notActive:
                    // 차례가 이미 넘어갔다 — 실려 온 state 로 맞춘다(편집기는 새 seq 로 다시 선다).
                    if let state = response.state {
                        self.applyState(state, ticket: ticket)
                    } else {
                        await self.refreshMatch(id: matchID)
                    }
                case .malformed:
                    if sameTurn { self.setNotice(RummyNoticeText.reason(.malformed, initialPoints: nil)) }
                case .unsupportedClient:
                    self.noteUpdateRequired()
                default:
                    retry = sameTurn
                }
            case .failure(let error)?:
                if self.isSchemaMissing(error) { self.noteServerMissing() }
                retry = sameTurn
            case nil:
                retry = sameTurn
            }
            if retry, self.editorKey == key {
                // 서버가 이 판을 못 받았다 — 다음 보내기가 같은 판이라고 건너뛰지 않게 기억을 지운다.
                self.lastSentDraft = nil
                if !self.draftDirty, self.draftRetryCount < Self.draftRetryLimit {
                    self.draftRetryCount += 1
                    self.scheduleDraft(after: Self.draftRetrySeconds)
                }
            }
            if self.draftDirty, self.editorKey == key {
                self.flushDraft()
            } else {
                self.draftDirty = false
            }
        }
    }

    /// 기다리던 디바운스를 걷는다(나가 있는 전송은 끝까지 간다 — 그 답은 `editorKey` 로 가린다).
    func cancelDraft() {
        draftDebounceTask?.cancel()
        draftDebounceTask = nil
        draftDirty = false
    }

    // MARK: - 마감

    /// 마감 + 유예가 지났으면 state 를 다시 읽는다(서버 `rummy__catchup` 이 시간 초과를 판정한다).
    /// 같은 차례면 3초 간격으로 세 번까지.
    package func checkDeadline(at now: Date) async {
        guard let current = match, current.status == .active,
              let deadline = deviceDate(serverMs: current.turnDeadlineMs) else { return }
        let grace = (current.graceMs.map { $0 / 1000 }) ?? Self.defaultGraceSeconds
        guard now >= deadline.addingTimeInterval(grace + Self.deadlineSlackSeconds) else { return }
        let key = "\(current.id.uuidString.lowercased())#\(current.seq ?? 0)"
        if deadlineFetchKey == key {
            guard deadlineFetchCount < Self.deadlineRetryLimit,
                  now.timeIntervalSince(lastDeadlineFetchAt) >= Self.deadlineRetrySeconds else { return }
            deadlineFetchCount += 1
        } else {
            deadlineFetchKey = key
            deadlineFetchCount = 1
        }
        lastDeadlineFetchAt = now
        await refreshMatch(id: current.id)
        // 여전히 같은 차례(서버가 아직 안 따라잡았다) — 한 번 더 깨운다.
        if let after = match, "\(after.id.uuidString.lowercased())#\(after.seq ?? 0)" == key {
            deadlineWakeKey = nil
            scheduleDeadlineWake()
        }
    }

    /// 창이 안 보여도 마감 + 유예 뒤 한 번 깨어나 state 를 다시 읽는다(차례 · 마감이 바뀔 때만 다시 건다).
    func scheduleDeadlineWake() {
        guard deadlineWakeEnabled, let current = match, current.status == .active,
              let deadline = deviceDate(serverMs: current.turnDeadlineMs) else {
            if deadlineTask != nil {
                deadlineTask?.cancel()
                deadlineTask = nil
                deadlineWakeKey = nil
            }
            return
        }
        let wakeKey = "\(current.id.uuidString.lowercased())#\(current.seq ?? 0)#\(current.turnDeadlineMs ?? 0)"
        guard deadlineWakeKey != wakeKey else { return }
        deadlineWakeKey = wakeKey
        deadlineTask?.cancel()
        let grace = (current.graceMs.map { $0 / 1000 }) ?? Self.defaultGraceSeconds
        var wake = deadline.addingTimeInterval(grace + Self.deadlineSlackSeconds)
        if deadlineFetchKey.map({ wakeKey.hasPrefix($0 + "#") }) == true {
            wake = max(wake, lastDeadlineFetchAt.addingTimeInterval(Self.deadlineRetrySeconds))
        }
        let delay = max(0, wake.timeIntervalSince(clock()))
        let generation = resetGeneration
        deadlineTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, generation == self.resetGeneration else { return }
            self.deadlineTask = nil
            await self.checkDeadline(at: self.clock())
        }
    }
}
